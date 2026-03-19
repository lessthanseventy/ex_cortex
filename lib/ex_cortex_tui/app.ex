defmodule ExCortexTUI.App do
  @moduledoc "Owl LiveScreen-based terminal UI for ExCortex."

  use GenServer

  import Ecto.Query

  alias ExCortexTUI.Router

  require Logger

  @screens %{
    cortex: ExCortexTUI.Screens.Cortex,
    daydreams: ExCortexTUI.Screens.Daydreams,
    proposals: ExCortexTUI.Screens.Proposals,
    wonder: ExCortexTUI.Screens.Wonder,
    muse: ExCortexTUI.Screens.Muse,
    hud: ExCortexTUI.Screens.HUD,
    logs: ExCortexTUI.Screens.Logs,
    help: ExCortexTUI.Screens.Help
  }

  @nav_items [
    {"c", :cortex, "Cortex"},
    {"d", :daydreams, "Daydreams"},
    {"p", :proposals, "Proposals"},
    {"w", :wonder, "Wonder"},
    {"m", :muse, "Muse"},
    {"h", :hud, "HUD"},
    {"l", :logs, "Logs"},
    {"?", :help, "Help"}
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Route logs to ring buffer instead of console
    ExCortexTUI.LogBuffer.start_link()

    # Install our log handler, suppress default console handler, re-enable logging
    :logger.add_handler(:tui_buffer, ExCortexTUI.LogHandler, %{})
    :logger.set_handler_config(:default, %{level: :none})
    Logger.configure(level: :debug)

    Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "signals")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "memory")

    # Switch to alternate screen buffer
    IO.write([IO.ANSI.clear(), "\e[?1049h", "\e[?25l"])

    ensure_live_screen()

    screen = :cortex
    screen_mod = Map.fetch!(@screens, screen)
    screen_state = safe_init(screen_mod, %{})

    state =
      update_status_counts(%{
        screen: screen,
        screen_mod: screen_mod,
        screen_state: screen_state,
        daydream_count: 0,
        proposal_count: 0
      })

    add_blocks(state)
    start_keyboard_reader()

    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    restore_terminal()
    :ok
  end

  @impl true
  # Arrow keys → j/k equivalents
  def handle_info({:key, :up}, state), do: handle_info({:key, "k"}, state)
  def handle_info({:key, :down}, state), do: handle_info({:key, "j"}, state)
  def handle_info({:key, :left}, state), do: handle_info({:key, "\e"}, state)
  def handle_info({:key, :right}, state), do: handle_info({:key, "\r"}, state)

  def handle_info({:key, "\e"}, %{screen: :cortex} = state) do
    {:noreply, state}
  end

  def handle_info({:key, "\e"}, state) do
    {:noreply, switch_screen(state, :cortex)}
  end

  def handle_info({:key, "q"}, %{screen: screen} = state) when screen not in [:wonder, :muse] do
    cleanup_and_quit()
    {:noreply, state}
  end

  def handle_info({:key, key}, state) do
    case Router.handle_key(key, state.screen) do
      {:switch, target} ->
        {:noreply, switch_screen(state, target)}

      :forward ->
        case safe_handle_key(state.screen_mod, key, state.screen_state) do
          {:noreply, new_screen_state} ->
            new_state = %{state | screen_state: new_screen_state}
            update_blocks(new_state)
            {:noreply, new_state}

          {:switch, target} ->
            {:noreply, switch_screen(state, target)}

          {:quit, _screen_state} ->
            cleanup_and_quit()
            {:noreply, state}
        end
    end
  end

  def handle_info(msg, state) do
    state = update_status_counts(state)

    case safe_handle_info(state.screen_mod, msg, state.screen_state) do
      {:noreply, new_screen_state} ->
        new_state = %{state | screen_state: new_screen_state}
        update_blocks(new_state)
        {:noreply, new_state}

      _ ->
        update_blocks(state)
        {:noreply, state}
    end
  end

  defp cleanup_and_quit do
    Owl.LiveScreen.flush()
    restore_terminal()
    Logger.configure(level: :debug)
    System.stop(0)
  end

  defp restore_terminal do
    beam_pid = :os.getpid() |> List.to_string()
    tty_path = "/proc/#{beam_pid}/fd/0"
    :os.cmd(~c"stty sane < #{tty_path} 2>/dev/null")
    IO.write(["\e[?25h", "\e[?1049l"])
  end

  defp switch_screen(state, target) do
    screen_mod = Map.get(@screens, target, Map.fetch!(@screens, :cortex))
    screen_state = safe_init(screen_mod, %{})

    new_state = %{
      state
      | screen: target,
        screen_mod: screen_mod,
        screen_state: screen_state
    }

    update_blocks(new_state)
    new_state
  end

  defp update_status_counts(state) do
    daydream_count =
      ExCortex.Repo.aggregate(
        from(d in ExCortex.Ruminations.Daydream, where: d.status == "running"),
        :count
      )

    proposal_count = length(ExCortex.Ruminations.list_proposals(status: "pending"))

    %{state | daydream_count: daydream_count, proposal_count: proposal_count}
  rescue
    _ -> %{state | daydream_count: 0, proposal_count: 0}
  end

  defp ensure_live_screen do
    unless Process.whereis(Owl.LiveScreen) do
      Owl.LiveScreen.start_link(refresh_every: 100)
    end
  end

  defp add_blocks(state) do
    Owl.LiveScreen.add_block(:header,
      state: state,
      render: &render_header/1
    )

    Owl.LiveScreen.add_block(:content,
      state: state,
      render: &render_content/1
    )

    Owl.LiveScreen.add_block(:status,
      state: state,
      render: &render_status/1
    )
  end

  defp update_blocks(state) do
    Owl.LiveScreen.update(:header, state)
    Owl.LiveScreen.update(:content, state)
    Owl.LiveScreen.update(:status, state)
  end

  defp render_header(state) do
    nav =
      Enum.map_intersperse(@nav_items, " ", fn {key, screen, label} ->
        if screen == state.screen do
          Owl.Data.tag("[#{key}]#{label}", [:bright, :cyan])
        else
          Owl.Data.tag("[#{key}]#{label}", :faint)
        end
      end)

    [Owl.Data.tag("ExCortex", :yellow), "  " | nav]
  end

  defp render_content(state) do
    safe_render(state.screen_mod, state.screen_state)
  end

  defp render_status(state) do
    [
      Owl.Data.tag(String.duplicate("─", 72), :faint),
      "\n",
      Owl.Data.tag("●", :green),
      " ready",
      "  daydreams:",
      Owl.Data.tag(to_string(state.daydream_count), :cyan),
      "  proposals:",
      Owl.Data.tag(to_string(state.proposal_count), :cyan),
      "  ",
      Owl.Data.tag("[q]quit [esc]back", :faint)
    ]
  end

  defp start_keyboard_reader do
    app_pid = self()

    # Get the BEAM's PID so we can access its terminal fd
    beam_pid = :os.getpid() |> List.to_string()
    tty_path = "/proc/#{beam_pid}/fd/0"

    # Spawn a shell that sets the BEAM's terminal to raw mode and reads from it
    # -icanon: disable line buffering (single keypress)
    # -echo: don't echo input
    # Keep opost/onlcr so \n still translates to \r\n for output
    cmd = "stty -icanon -echo < #{tty_path} 2>/dev/null; exec cat < #{tty_path}"
    port = Port.open({:spawn, "sh -c '#{cmd}'"}, [:binary, :eof])

    Task.start_link(fn -> read_port_loop(port, app_pid) end)
  end

  defp read_port_loop(port, app_pid) do
    receive do
      {^port, {:data, data}} ->
        # Parse escape sequences for arrow keys
        parse_keys(data, app_pid)
        read_port_loop(port, app_pid)

      {^port, :eof} ->
        :ok
    end
  end

  defp parse_keys(<<"\e[A" :: binary>>, pid), do: send(pid, {:key, :up})
  defp parse_keys(<<"\e[B" :: binary>>, pid), do: send(pid, {:key, :down})
  defp parse_keys(<<"\e[C" :: binary>>, pid), do: send(pid, {:key, :right})
  defp parse_keys(<<"\e[D" :: binary>>, pid), do: send(pid, {:key, :left})
  defp parse_keys(<<"\e" :: binary>>, pid), do: send(pid, {:key, "\e"})
  defp parse_keys(<<"\r" :: binary>>, pid), do: send(pid, {:key, "\r"})
  defp parse_keys(<<"\n" :: binary>>, pid), do: send(pid, {:key, "\r"})
  defp parse_keys(<<3 :: integer>>, pid), do: send(pid, {:key, <<3>>})  # Ctrl+C
  defp parse_keys(<<127 :: integer>>, pid), do: send(pid, {:key, <<127>>})  # Backspace
  defp parse_keys(<<c :: integer>>, pid) when c >= 32 and c < 127, do: send(pid, {:key, <<c>>})
  defp parse_keys(data, pid) when byte_size(data) > 1 do
    # Multi-byte sequence — try to parse each byte
    for <<byte <- data>> do
      parse_keys(<<byte>>, pid)
    end
  end
  defp parse_keys(_, _pid), do: :ok

  # Safe wrappers that handle screens not implementing the behaviour yet

  defp safe_init(module, args) do
    Code.ensure_loaded(module)

    if function_exported?(module, :init, 1) do
      module.init(args)
    else
      %{}
    end
  rescue
    e ->
      Logger.warning("[TUI] Screen init failed: #{inspect(module)} — #{Exception.message(e)}")
      %{}
  end

  defp safe_render(module, screen_state) do
    # Ensure module is loaded (may not be loaded yet in release mode)
    Code.ensure_loaded(module)

    if function_exported?(module, :render, 1) do
      module.render(screen_state)
    else
      Owl.Data.tag("  Coming soon... (#{inspect(module)})", :faint)
    end
  rescue
    e -> Owl.Data.tag("  Screen error: #{Exception.message(e)}", :red)
  end

  defp safe_handle_key(module, key, screen_state) do
    if function_exported?(module, :handle_key, 2) do
      module.handle_key(key, screen_state)
    else
      {:noreply, screen_state}
    end
  rescue
    _ -> {:noreply, screen_state}
  end

  defp safe_handle_info(module, msg, screen_state) do
    if function_exported?(module, :handle_info, 2) do
      module.handle_info(msg, screen_state)
    else
      {:noreply, screen_state}
    end
  rescue
    _ -> {:noreply, screen_state}
  end
end
