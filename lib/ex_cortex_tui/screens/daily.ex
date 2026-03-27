defmodule ExCortexTUI.Screens.Daily do
  @moduledoc "Daily notes screen — Obsidian todos, brain dump, what happened."
  @behaviour ExCortexTUI.Screen

  alias ExCortex.Signals.TodoSync
  alias ExCortex.Tools.DailyNoteWrite
  alias ExCortex.Tools.ObsidianTodos

  @impl true
  def init(_opts) do
    Task.start(fn -> TodoSync.sync() end)
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "signals")
    %{signal: load_daily_signal(), scroll: 0, mode: :browse, input: "", input_target: nil}
  end

  @impl true
  def render(%{mode: :input} = state) do
    browse_lines = render_browse(state)
    prompt = input_prompt(state.input_target)

    browse_lines ++
      [
        "\n",
        Owl.Data.tag(String.duplicate("─", 60), :faint),
        "\n",
        Owl.Data.tag(prompt, :cyan),
        state.input,
        Owl.Data.tag("▌", :faint)
      ]
  end

  def render(state) do
    render_browse(state)
  end

  @impl true
  # -- Input mode keys --
  def handle_key("\r", %{mode: :input, input: ""} = state) do
    {:noreply, %{state | mode: :browse, input_target: nil}}
  end

  def handle_key("\r", %{mode: :input} = state) do
    submit_input(state)
  end

  def handle_key(<<127>>, %{mode: :input} = state) do
    {:noreply, %{state | input: String.slice(state.input, 0..-2//1)}}
  end

  def handle_key(<<c>> = char, %{mode: :input} = state) when c >= 32 and c < 127 do
    {:noreply, %{state | input: state.input <> char}}
  end

  def handle_key(_key, %{mode: :input} = state), do: {:noreply, state}

  # -- Browse mode keys --
  def handle_key("j", state), do: {:noreply, %{state | scroll: state.scroll + 3}}
  def handle_key("k", state), do: {:noreply, %{state | scroll: max(state.scroll - 3, 0)}}

  def handle_key("r", state) do
    Task.start(fn -> TodoSync.sync() end)
    {:noreply, %{state | signal: load_daily_signal(), scroll: 0}}
  end

  # Toggle todo by number (1-9)
  def handle_key(<<n>>, state) when n >= ?1 and n <= ?9 do
    index = n - ?1
    toggle_todo(state, index)
  end

  # Input modes
  def handle_key("t", state), do: {:noreply, %{state | mode: :input, input: "", input_target: :todo}}
  def handle_key("b", state), do: {:noreply, %{state | mode: :input, input: "", input_target: :brain_dump}}
  def handle_key("e", state), do: {:noreply, %{state | mode: :input, input: "", input_target: :what_happened}}

  def handle_key(_key, state), do: {:noreply, state}

  @impl true
  def handle_info({:signal_posted, _}, state) do
    {:noreply, %{state | signal: load_daily_signal()}}
  end

  def handle_info(_, state), do: {:noreply, state}

  # -- Data --

  defp load_daily_signal do
    Enum.find(ExCortex.Signals.list_signals(), fn s -> s.pin_slug == "daily-todos" end)
  rescue
    _ -> nil
  end

  # -- Actions --

  defp toggle_todo(state, index) do
    items = get_in(state.signal.metadata, ["items"]) || []

    case Enum.at(items, index) do
      %{"text" => text, "checked" => checked} ->
        Task.start(fn ->
          ObsidianTodos.toggle_todo(%{"text" => text, "done" => !checked})
          TodoSync.sync()
        end)

        # Optimistic update
        new_items = List.update_at(items, index, &Map.put(&1, "checked", !checked))
        new_signal = put_in(state.signal.metadata, ["items"], new_items)
        {:noreply, %{state | signal: new_signal}}

      _ ->
        {:noreply, state}
    end
  end

  defp submit_input(state) do
    text = String.trim(state.input)

    Task.start(fn ->
      case state.input_target do
        :todo ->
          ObsidianTodos.add_todo(%{"text" => text})

        :brain_dump ->
          DailyNoteWrite.call(%{"content" => text, "section" => "brain dump"})

        :what_happened ->
          DailyNoteWrite.call(%{"content" => text, "section" => "what happened"})
      end

      TodoSync.sync()
    end)

    {:noreply, %{state | mode: :browse, input: "", input_target: nil}}
  end

  # -- Rendering --

  defp render_browse(state) do
    all_lines = state.signal |> render_content() |> to_lines()
    height = terminal_height() - 4
    # Clamp scroll
    max_scroll = max(length(all_lines) - height, 0)
    offset = min(state.scroll, max_scroll)

    all_lines
    |> Enum.drop(offset)
    |> Enum.take(height)
    |> Enum.intersperse("\n")
  end

  defp render_content(nil) do
    [Owl.Data.tag("No daily note synced yet. Press r to refresh.", :faint)]
  end

  defp render_content(signal) do
    title = signal.title || "Today"
    items = get_in(signal.metadata, ["items"]) || []
    brain_dump = get_in(signal.metadata, ["brain_dump"]) || []
    what_happened = get_in(signal.metadata, ["what_happened"]) || []

    List.flatten([
      Owl.Data.tag(title, [:bright, :yellow]),
      "\n",
      "\n",
      render_todos("what's happening", items),
      "\n",
      "\n",
      render_bullets("brain dump", brain_dump),
      "\n",
      "\n",
      render_what_happened("what happened", what_happened),
      "\n",
      "\n",
      Owl.Data.tag("[j/k]scroll [1-9]toggle [t]add todo [b]brain dump [e]event [r]refresh", :faint)
    ])
  end

  defp render_todos(title, items) do
    header = Owl.Data.tag(title, [:bright, :cyan])

    body =
      if Enum.empty?(items) do
        ["\n", "  ", Owl.Data.tag("(empty)", :faint)]
      else
        items
        |> Enum.with_index(1)
        |> Enum.map(fn {item, num} ->
          ["\n", "  ", render_numbered_todo(item, num)]
        end)
      end

    [header | List.flatten(body)]
  end

  defp render_numbered_todo(%{"text" => text, "checked" => true}, num) do
    [Owl.Data.tag("#{num}.", :faint), " ", Owl.Data.tag("[x] #{text}", [:faint])]
  end

  defp render_numbered_todo(%{"text" => text}, num) do
    [Owl.Data.tag("#{num}.", :cyan), " ", Owl.Data.tag("[ ] ", :yellow), text]
  end

  defp render_numbered_todo(item, num) when is_binary(item) do
    [Owl.Data.tag("#{num}.", :cyan), " ", item]
  end

  defp render_bullets(title, items) do
    header = Owl.Data.tag(title, [:bright, :cyan])

    body =
      if Enum.empty?(items) do
        ["\n", "  ", Owl.Data.tag("(empty)", :faint)]
      else
        Enum.map(items, fn
          item when is_binary(item) -> ["\n", "  • ", item]
          %{"text" => text} -> ["\n", "  • ", text]
          _ -> []
        end)
      end

    [header | List.flatten(body)]
  end

  defp render_what_happened(title, items) do
    header = Owl.Data.tag(title, [:bright, :cyan])

    body =
      if Enum.empty?(items) do
        ["\n", "  ", Owl.Data.tag("(empty)", :faint)]
      else
        Enum.map(items, fn
          %{"text" => text, "checked" => true} ->
            ["\n", "  ", Owl.Data.tag("[x] #{text}", :faint)]

          %{"text" => text} ->
            ["\n", "  ", Owl.Data.tag("[ ] ", :yellow), text]

          item when is_binary(item) ->
            ["\n", "  • ", item]

          _ ->
            []
        end)
      end

    [header | List.flatten(body)]
  end

  defp input_prompt(:todo), do: "new todo: "
  defp input_prompt(:brain_dump), do: "brain dump: "
  defp input_prompt(:what_happened), do: "what happened: "
  defp input_prompt(_), do: "> "

  defp to_lines(data) do
    data
    |> List.flatten()
    |> Enum.map_join(fn
      item when is_binary(item) -> item
      item -> item |> Owl.Data.to_chardata() |> IO.chardata_to_string()
    end)
    |> String.split("\n")
  end

  defp terminal_height do
    case :io.rows() do
      {:ok, rows} -> rows
      _ -> 24
    end
  end
end
