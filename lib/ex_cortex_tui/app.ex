defmodule ExCortexTUI.App do
  @moduledoc "Ratatouille-based terminal UI for ExCortex."

  @behaviour Ratatouille.App

  import Ecto.Query
  import Ratatouille.View

  alias ExCortex.Ruminations.Daydream
  alias ExCortex.Signals.TodoSync
  alias ExCortex.Tools.ObsidianTodos
  alias Ratatouille.Runtime.Command
  alias Ratatouille.Runtime.Subscription

  require Logger

  @nav_items [
    {?a, :daily, "Daily"},
    {?c, :cortex, "Cortex"},
    {?d, :daydreams, "Daydreams"},
    {?p, :proposals, "Proposals"},
    {?w, :wonder, "Wonder"},
    {?m, :muse, "Muse"},
    {?h, :hud, "HUD"},
    {?l, :logs, "Logs"},
    {??, :help, "Help"}
  ]

  @nav_keys Map.new(@nav_items, fn {ch, screen, _} -> {ch, screen} end)
  @chat_screens [:wonder, :muse]

  # ── Ratatouille.App callbacks ──────────────────────────────────────

  @impl true
  def init(%{window: window}) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "signals")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "memory")

    %{
      screen: :daily,
      window: window,
      scroll: 0,
      cursor: 0,
      input: nil,
      input_mode: nil,
      chat_history: [],
      chat_response: "",
      chat_streaming: false,
      daydream_count: safe_daydream_count(),
      proposal_count: safe_proposal_count(),
      daily_signal: load_daily_signal(),
      daydreams: [],
      proposals: [],
      detail: nil
    }
  end

  @impl true
  def subscribe(_model) do
    Subscription.interval(3_000, :tick)
  end

  @impl true
  def update(model, msg) do
    case msg do
      # Tick — refresh counts
      :tick ->
        %{model | daydream_count: safe_daydream_count(), proposal_count: safe_proposal_count()}

      # PubSub messages
      {:daydream_started, _} ->
        refresh_screen_data(model)

      {:daydream_completed, _} ->
        refresh_screen_data(model)

      {:signal_updated, _} ->
        refresh_screen_data(model)

      {:engram_updated, _} ->
        refresh_screen_data(model)

      # Command results
      {:daily_signal_loaded, signal} ->
        %{model | daily_signal: signal}

      {:screen_data, data} ->
        Map.merge(model, data)

      {:todo_synced, _} ->
        {%{model | daily_signal: load_daily_signal()}, load_daily_cmd()}

      {:chat_token, token} ->
        %{model | chat_response: model.chat_response <> token}

      {:chat_done, _} ->
        finish_chat(model)

      {:chat_error, err} ->
        finish_chat_error(model, err)

      # Keyboard events
      {:event, event} ->
        handle_key(model, event)

      # Resize
      {:resize, _event} ->
        model

      _ ->
        model
    end
  end

  @impl true
  def render(model) do
    nav_text =
      @nav_items
      |> Enum.map_join(" ", fn {ch, screen, name} ->
        if screen == model.screen, do: "[#{<<ch>>}]#{name}", else: " #{<<ch>>} #{name}"
      end)

    top =
      bar do
        label(content: "ExCortex  #{nav_text}")
      end

    status = "● daydreams:#{model.daydream_count}  proposals:#{model.proposal_count}  [q]quit [esc]back"

    bottom =
      bar do
        label(content: status)
      end

    view top_bar: top, bottom_bar: bottom do
      render_screen(model)
    end
  rescue
    e ->
      view do
        label(content: "Render error: #{Exception.message(e)}")
      end
  end

  # ── Key handling ───────────────────────────────────────────────────

  defp handle_key(model, %{key: key}) when key > 0 do
    handle_special_key(model, key)
  end

  defp handle_key(model, %{ch: ch}) when ch > 0 do
    handle_char(model, ch)
  end

  defp handle_key(model, _event), do: model

  # Escape key = 27
  defp handle_special_key(%{input: input} = model, 27) when not is_nil(input) do
    %{model | input: nil, input_mode: nil}
  end

  defp handle_special_key(%{screen: :daily} = model, 27), do: model

  defp handle_special_key(model, 27) do
    switch_screen(model, :daily)
  end

  # Enter key
  defp handle_special_key(%{input: input, input_mode: mode} = model, 13) when not is_nil(input) do
    submit_input(model, mode, input)
  end

  defp handle_special_key(%{screen: :daydreams} = model, 13) do
    show_daydream_detail(model)
  end

  defp handle_special_key(model, 13), do: model

  # Arrow up
  defp handle_special_key(model, 65_517), do: handle_char(model, ?k)
  # Arrow down
  defp handle_special_key(model, 65_516), do: handle_char(model, ?j)

  # Backspace (key 127 or 65522)
  defp handle_special_key(%{input: input} = model, key) when key in [127, 65_522] and not is_nil(input) do
    %{model | input: String.slice(input, 0..-2//1)}
  end

  defp handle_special_key(model, _key), do: model

  # When in input mode, accumulate chars
  defp handle_char(%{input: input} = model, ch) when not is_nil(input) and ch >= 32 do
    %{model | input: input <> <<ch::utf8>>}
  end

  # Chat screens: typing starts input mode
  defp handle_char(%{screen: screen, input: nil} = model, ch)
       when screen in @chat_screens and ch >= 32 and ch not in [?q] do
    %{model | input: <<ch::utf8>>, input_mode: :chat}
  end

  # Nav keys (not in chat screens)
  defp handle_char(%{screen: screen} = model, ch) when screen not in @chat_screens do
    case Map.get(@nav_keys, ch) do
      nil -> handle_screen_char(model, ch)
      target -> switch_screen(model, target)
    end
  end

  defp handle_char(model, _ch), do: model

  # Screen-specific char handling
  defp handle_screen_char(%{screen: :daily} = model, ?j), do: scroll_down(model)
  defp handle_screen_char(%{screen: :daily} = model, ?k), do: scroll_up(model)

  defp handle_screen_char(%{screen: :daily} = model, ?r) do
    {%{model | daily_signal: load_daily_signal()}, load_daily_cmd()}
  end

  defp handle_screen_char(%{screen: :daily} = model, ?t) do
    %{model | input: "", input_mode: :todo}
  end

  defp handle_screen_char(%{screen: :daily} = model, ?b) do
    %{model | input: "", input_mode: :brain_dump}
  end

  defp handle_screen_char(%{screen: :daily} = model, ?e) do
    %{model | input: "", input_mode: :what_happened}
  end

  defp handle_screen_char(%{screen: :daily} = model, ch) when ch in ?1..?9 do
    toggle_daily_todo(model, ch - ?0)
  end

  defp handle_screen_char(%{screen: :cortex} = model, ?j), do: scroll_down(model)
  defp handle_screen_char(%{screen: :cortex} = model, ?k), do: scroll_up(model)

  defp handle_screen_char(%{screen: :daydreams} = model, ?j), do: cursor_down(model)
  defp handle_screen_char(%{screen: :daydreams} = model, ?k), do: cursor_up(model)

  defp handle_screen_char(%{screen: :proposals} = model, ?j), do: cursor_down(model)
  defp handle_screen_char(%{screen: :proposals} = model, ?k), do: cursor_up(model)

  defp handle_screen_char(%{screen: :proposals} = model, ?y) do
    approve_current_proposal(model)
  end

  defp handle_screen_char(%{screen: :proposals} = model, ?n) do
    reject_current_proposal(model)
  end

  defp handle_screen_char(%{screen: :logs} = model, ?j), do: scroll_down(model)
  defp handle_screen_char(%{screen: :logs} = model, ?k), do: scroll_up(model)
  defp handle_screen_char(model, _ch), do: model

  # ── Screen switching ───────────────────────────────────────────────

  defp switch_screen(model, target) do
    base = %{model | screen: target, scroll: 0, cursor: 0, input: nil, input_mode: nil, detail: nil}

    case target do
      :daily ->
        %{base | daily_signal: load_daily_signal()}

      :daydreams ->
        %{base | daydreams: load_daydreams()}

      :proposals ->
        %{base | proposals: load_proposals()}

      _ ->
        base
    end
  end

  defp refresh_screen_data(model) do
    model
    |> Map.put(:daydream_count, safe_daydream_count())
    |> Map.put(:proposal_count, safe_proposal_count())
    |> then(fn m ->
      case m.screen do
        :daily -> %{m | daily_signal: load_daily_signal()}
        :daydreams -> %{m | daydreams: load_daydreams()}
        :proposals -> %{m | proposals: load_proposals()}
        _ -> m
      end
    end)
  end

  # ── Screen rendering ──────────────────────────────────────────────

  defp render_screen(%{screen: :daily} = model), do: render_daily(model)
  defp render_screen(%{screen: :cortex} = model), do: render_cortex(model)
  defp render_screen(%{screen: :daydreams} = model), do: render_daydreams(model)
  defp render_screen(%{screen: :proposals} = model), do: render_proposals(model)
  defp render_screen(%{screen: :wonder} = model), do: render_chat(model, "Wonder")
  defp render_screen(%{screen: :muse} = model), do: render_chat(model, "Muse")
  defp render_screen(%{screen: :hud} = model), do: render_hud(model)
  defp render_screen(%{screen: :logs} = model), do: render_logs(model)
  defp render_screen(%{screen: :help}), do: render_help()
  defp render_screen(_model), do: label(content: "Unknown screen")

  # ── Daily screen ──────────────────────────────────────────────────

  defp render_daily(model) do
    signal = model.daily_signal
    items = get_in_meta(signal, "items") || []
    brain_dump = get_in_meta(signal, "brain_dump") || []
    what_happened = get_in_meta(signal, "what_happened") || []

    viewport offset_y: model.scroll do
      panel title: "Daily Todos [t]add [1-9]toggle [r]refresh [b]brain dump [e]what happened" do
        if items == [] do
          label(content: "  No todos found. Press [r] to refresh.")
        else
          for {item, idx} <- Enum.with_index(items, 1) do
            checked = item["checked"] || item["done"] || false
            marker = if checked, do: "[x]", else: "[ ]"
            num = if idx <= 9, do: "#{idx}.", else: "  "
            label(content: "  #{num} #{marker} #{item["text"] || item["title"] || "?"}")
          end
        end

        if brain_dump != [] do
          label(content: "")
          label(content: "  Brain Dump:", attributes: [:bold])

          for item <- brain_dump do
            label(content: "    - #{item_text(item)}")
          end
        end

        if what_happened != [] do
          label(content: "")
          label(content: "  What Happened:", attributes: [:bold])

          for item <- what_happened do
            checked = if is_map(item) && item["checked"], do: "[x] ", else: "    "
            label(content: "  #{checked}#{item_text(item)}")
          end
        end

        render_input_box(model)
      end
    end
  end

  # ── Cortex screen ─────────────────────────────────────────────────

  defp render_cortex(model) do
    viewport offset_y: model.scroll do
      row do
        column size: 6 do
          panel title: "Ruminations" do
            for r <- safe_list_ruminations() do
              label(content: "  #{r.name}")
            end
          end

          panel title: "Signals" do
            for s <- safe_list_signals() do
              label(content: "  [#{s.type || "?"}] #{s.title}")
            end
          end
        end

        column size: 6 do
          panel title: "Clusters" do
            for c <- safe_list_pathways() do
              label(content: "  #{c.cluster_name}")
            end
          end

          panel title: "Memory" do
            for e <- safe_list_engrams() do
              label(content: "  #{e.impression || e.title || "untitled"}")
            end
          end
        end
      end
    end
  end

  # ── Daydreams screen ──────────────────────────────────────────────

  defp render_daydreams(%{detail: %{} = detail} = _model) do
    panel title: "Daydream Detail [esc] back" do
      label(content: "  Rumination: #{detail.rumination_name}")
      label(content: "  Status: #{detail.status}")
      label(content: "  Started: #{detail.inserted_at}")
      label(content: "  Input: #{truncate(inspect(detail.input), 80)}")

      if detail.synapse_results do
        label(content: "")
        label(content: "  Synapse Results:", attributes: [:bold])

        for {name, result} <- detail.synapse_results do
          label(content: "    #{name}: #{truncate(inspect(result), 60)}")
        end
      end
    end
  end

  defp render_daydreams(model) do
    daydreams = model.daydreams

    panel title: "Daydreams [j/k]navigate [enter]detail" do
      if daydreams == [] do
        label(content: "  No recent daydreams.")
      else
        for {d, idx} <- Enum.with_index(daydreams) do
          prefix = if idx == model.cursor, do: " > ", else: "   "
          name = (d.rumination && d.rumination.name) || "?"
          color = status_color(d.status)
          label(content: "#{prefix}[#{d.status}] #{name} — #{format_time(d.inserted_at)}", color: color)
        end
      end
    end
  end

  # ── Proposals screen ──────────────────────────────────────────────

  defp render_proposals(model) do
    proposals = model.proposals

    panel title: "Proposals [j/k]navigate [y]approve [n]reject" do
      if proposals == [] do
        label(content: "  No pending proposals.")
      else
        for {p, idx} <- Enum.with_index(proposals) do
          prefix = if idx == model.cursor, do: " > ", else: "   "
          desc = truncate(p.description || "?", 60)
          label(content: "#{prefix}[#{p.status}] #{desc}")
        end
      end
    end
  end

  # ── Chat screen (Wonder / Muse) ───────────────────────────────────

  defp render_chat(model, title) do
    panel title: "#{title} — type to chat, Enter to send, Esc to cancel" do
      for {role, content} <- model.chat_history do
        color = if role == :user, do: :cyan, else: :green

        label do
          text(content: "#{role}: ", color: color, attributes: [:bold])
          text(content: truncate(content, 200))
        end
      end

      if model.chat_streaming do
        label do
          text(content: "assistant: ", color: :green, attributes: [:bold])
          text(content: model.chat_response <> "...")
        end
      end

      if model.input do
        label(content: "")

        label do
          text(content: "> ", color: :yellow)
          text(content: model.input)
          text(content: "█", color: :yellow)
        end
      end
    end
  end

  # ── HUD screen ────────────────────────────────────────────────────

  defp render_hud(_model) do
    hud_text =
      try do
        ExCortexTUI.HUD.Formatter.format(ExCortexTUI.HUD.gather_state())
      rescue
        _ -> "HUD unavailable"
      end

    panel title: "HUD" do
      for line <- String.split(hud_text, "\n") do
        label(content: line)
      end
    end
  end

  # ── Logs screen ───────────────────────────────────────────────────

  defp render_logs(model) do
    lines =
      try do
        ExCortexTUI.LogBuffer.get_lines(40)
      rescue
        _ -> []
      end

    viewport offset_y: model.scroll do
      panel title: "Logs [j/k]scroll" do
        if lines == [] do
          label(content: "  No log entries.")
        else
          for line <- lines do
            label(content: "  #{line}")
          end
        end
      end
    end
  end

  # ── Help screen ───────────────────────────────────────────────────

  defp render_help do
    panel title: "Key Bindings" do
      label(content: "  Navigation:")
      label(content: "    a  Daily          c  Cortex        d  Daydreams")
      label(content: "    p  Proposals      w  Wonder        m  Muse")
      label(content: "    h  HUD            l  Logs          ?  Help")
      label(content: "")
      label(content: "  General:")
      label(content: "    j/k    Scroll / navigate")
      label(content: "    Enter  Select / submit")
      label(content: "    Esc    Back / cancel")
      label(content: "    q      Quit (not in chat)")
      label(content: "    Ctrl+C Force quit")
      label(content: "")
      label(content: "  Daily:")
      label(content: "    1-9  Toggle todo       t  Add todo")
      label(content: "    b    Brain dump         e  What happened")
      label(content: "    r    Refresh")
      label(content: "")
      label(content: "  Proposals:")
      label(content: "    y  Approve              n  Reject")
      label(content: "")
      label(content: "  Chat (Wonder/Muse):")
      label(content: "    Type to enter input, Enter to send")
    end
  end

  # ── Input handling ─────────────────────────────────────────────────

  defp render_input_box(%{input: nil}), do: []

  defp render_input_box(%{input: input, input_mode: mode}) do
    mode_label =
      case mode do
        :todo -> "New todo"
        :brain_dump -> "Brain dump"
        :what_happened -> "What happened"
        _ -> "Input"
      end

    [
      label(content: ""),
      label do
        text(content: "  #{mode_label}: ", color: :yellow, attributes: [:bold])
        text(content: input)
        text(content: "█", color: :yellow)
      end
    ]
  end


  defp submit_input(model, :todo, text) do
    {%{model | input: nil, input_mode: nil}, todo_add_cmd(text)}
  end

  defp submit_input(model, :brain_dump, text) do
    {%{model | input: nil, input_mode: nil}, daily_write_cmd(text, "brain dump")}
  end

  defp submit_input(model, :what_happened, text) do
    {%{model | input: nil, input_mode: nil}, daily_write_cmd(text, "what happened")}
  end

  defp submit_input(model, :chat, text) do
    scope = if model.screen == :wonder, do: "wonder", else: "muse"
    history = model.chat_history ++ [{:user, text}]
    runtime_pid = self()

    cmd =
      Command.new(
        fn ->
          callback = fn
            {:token, t} -> send(runtime_pid, {:command_result, {:chat_token, t}})
            :done -> send(runtime_pid, {:command_result, {:chat_done, nil}})
            {:error, e} -> send(runtime_pid, {:command_result, {:chat_error, e}})
          end

          ExCortex.Muse.stream_ask(text, callback, scope: scope)
        end,
        :chat_started
      )

    {%{model | input: nil, input_mode: nil, chat_history: history, chat_response: "", chat_streaming: true}, cmd}
  end

  defp submit_input(model, _mode, _text) do
    %{model | input: nil, input_mode: nil}
  end

  defp finish_chat(model) do
    history = model.chat_history ++ [{:assistant, model.chat_response}]
    %{model | chat_history: history, chat_response: "", chat_streaming: false}
  end

  defp finish_chat_error(model, err) do
    history = model.chat_history ++ [{:assistant, "Error: #{inspect(err)}"}]
    %{model | chat_history: history, chat_response: "", chat_streaming: false}
  end

  # ── Daily actions ──────────────────────────────────────────────────

  defp toggle_daily_todo(model, index) do
    items = get_in_meta(model.daily_signal, "items") || []

    case Enum.at(items, index - 1) do
      nil ->
        model

      item ->
        text = item["text"] || item["title"]
        checked = item["checked"] || item["done"] || false

        cmd =
          Command.new(
            fn ->
              ObsidianTodos.toggle_todo(%{"text" => text, "done" => !checked})
              TodoSync.sync()
            end,
            {:todo_synced, nil}
          )

        {model, cmd}
    end
  end

  defp todo_add_cmd(text) do
    Command.new(
      fn ->
        ObsidianTodos.add_todo(%{"text" => text})
        TodoSync.sync()
      end,
      {:todo_synced, nil}
    )
  end

  defp daily_write_cmd(text, section) do
    Command.new(
      fn ->
        ExCortex.Tools.DailyNoteWrite.call(%{"content" => text, "section" => section})
        TodoSync.sync()
      end,
      {:todo_synced, nil}
    )
  end

  # ── Proposal actions ──────────────────────────────────────────────

  defp approve_current_proposal(model) do
    case Enum.at(model.proposals, model.cursor) do
      nil ->
        model

      proposal ->
        cmd =
          Command.new(
            fn -> ExCortex.Ruminations.approve_proposal(proposal) end,
            {:screen_data, %{proposals: load_proposals()}}
          )

        {model, cmd}
    end
  end

  defp reject_current_proposal(model) do
    case Enum.at(model.proposals, model.cursor) do
      nil ->
        model

      proposal ->
        cmd =
          Command.new(
            fn -> ExCortex.Ruminations.reject_proposal(proposal) end,
            {:screen_data, %{proposals: load_proposals()}}
          )

        {model, cmd}
    end
  end

  # ── Daydream detail ────────────────────────────────────────────────

  defp show_daydream_detail(model) do
    case Enum.at(model.daydreams, model.cursor) do
      nil ->
        model

      d ->
        detail = %{
          rumination_name: (d.rumination && d.rumination.name) || "?",
          status: d.status,
          inserted_at: format_time(d.inserted_at),
          input: d.input,
          synapse_results: d.synapse_results
        }

        %{model | detail: detail}
    end
  end

  # ── Scroll / cursor helpers ────────────────────────────────────────

  defp scroll_down(model), do: %{model | scroll: model.scroll + 1}
  defp scroll_up(model), do: %{model | scroll: max(0, model.scroll - 1)}
  defp cursor_down(model), do: %{model | cursor: model.cursor + 1}
  defp cursor_up(model), do: %{model | cursor: max(0, model.cursor - 1)}

  # ── Data loading (safe — always rescue) ────────────────────────────

  defp load_daily_signal do
    Enum.find(ExCortex.Signals.list_signals(), &(&1.pin_slug == "daily-todos"))
  rescue
    _ -> nil
  end

  defp load_daily_cmd do
    Command.new(fn -> load_daily_signal() end, {:daily_signal_loaded, nil})
  end

  defp load_daydreams do
    ExCortex.Repo.all(
      from(d in Daydream,
        order_by: [desc: d.inserted_at],
        limit: 20,
        preload: [:rumination]
      )
    )
  rescue
    _ -> []
  end

  defp load_proposals do
    ExCortex.Ruminations.list_proposals(status: "pending")
  rescue
    _ -> []
  end

  defp safe_daydream_count do
    ExCortex.Repo.aggregate(
      from(d in Daydream, where: d.status == "running"),
      :count
    )
  rescue
    _ -> 0
  end

  defp safe_proposal_count do
    length(ExCortex.Ruminations.list_proposals(status: "pending"))
  rescue
    _ -> 0
  end

  defp safe_list_ruminations do
    Enum.take(ExCortex.Ruminations.list_ruminations(), 5)
  rescue
    _ -> []
  end

  defp safe_list_signals do
    ExCortex.Signals.list_signals(limit: 5)
  rescue
    _ -> []
  end

  defp safe_list_pathways do
    Enum.take(ExCortex.Clusters.list_pathways(), 5)
  rescue
    _ -> []
  end

  defp safe_list_engrams do
    ExCortex.Memory.list_engrams(limit: 5)
  rescue
    _ -> []
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp get_in_meta(nil, _key), do: nil

  defp get_in_meta(signal, key) do
    meta = signal.metadata || %{}
    Map.get(meta, key)
  end

  defp status_color("running"), do: :yellow
  defp status_color("completed"), do: :green
  defp status_color("failed"), do: :red
  defp status_color("interrupted"), do: :magenta
  defp status_color(_), do: :white

  defp format_time(nil), do: "?"

  defp format_time(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: "?"

  defp truncate(nil, _len), do: ""
  defp truncate(s, len) when is_binary(s) and byte_size(s) <= len, do: s
  defp truncate(s, len) when is_binary(s), do: String.slice(s, 0, len) <> "..."
  defp truncate(s, len), do: truncate(inspect(s), len)

  defp item_text(%{"text" => text}), do: text
  defp item_text(%{"title" => title}), do: title
  defp item_text(item) when is_binary(item), do: item
  defp item_text(item), do: inspect(item)
end
