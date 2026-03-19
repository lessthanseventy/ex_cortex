defmodule ExCortexTUI.Screens.Daily do
  @moduledoc "Daily notes screen — Obsidian todos, brain dump, what happened."
  @behaviour ExCortexTUI.Screen

  @impl true
  def init(_opts) do
    # Trigger a sync on screen entry
    Task.start(fn -> ExCortex.Signals.TodoSync.sync() end)

    Phoenix.PubSub.subscribe(ExCortex.PubSub, "signals")
    %{signal: load_daily_signal(), scroll: 0}
  end

  @impl true
  def render(state) do
    lines = render_content(state.signal) |> to_lines()
    visible_height = terminal_height() - 4
    offset = min(state.scroll, max(length(lines) - visible_height, 0))

    lines
    |> Enum.drop(offset)
    |> Enum.take(visible_height)
    |> Enum.intersperse("\n")
  end

  @impl true
  def handle_key("j", state), do: {:noreply, %{state | scroll: state.scroll + 3}}
  def handle_key("k", state), do: {:noreply, %{state | scroll: max(state.scroll - 3, 0)}}
  def handle_key("r", state), do: {:noreply, %{state | signal: load_daily_signal(), scroll: 0}}
  def handle_key(_key, state), do: {:noreply, state}

  @impl true
  def handle_info({:signal_posted, _}, state) do
    {:noreply, %{state | signal: load_daily_signal()}}
  end

  def handle_info(_, state), do: {:noreply, state}

  # -- Data --

  defp load_daily_signal do
    ExCortex.Signals.list_signals()
    |> Enum.find(fn s -> s.pin_slug == "daily-todos" end)
  rescue
    _ -> nil
  end

  # -- Rendering --

  defp render_content(nil) do
    [Owl.Data.tag("No daily note synced yet. Press r to refresh.", :faint)]
  end

  defp render_content(signal) do
    title = signal.title || "Today"
    items = get_in(signal.metadata, ["items"]) || []
    brain_dump = get_in(signal.metadata, ["brain_dump"]) || []
    what_happened = get_in(signal.metadata, ["what_happened"]) || []

    [
      Owl.Data.tag(title, [:bright, :yellow]),
      "\n\n",
      render_section("what's happening", items, &render_todo/1),
      "\n",
      render_section("brain dump", brain_dump, &render_bullet/1),
      "\n",
      render_section("what happened", what_happened, &render_todo_or_bullet/1),
      "\n",
      Owl.Data.tag("[j/k] scroll  [r] refresh  [Esc/Ctrl+D] back", :faint)
    ]
  end

  defp render_section(title, items, renderer) do
    header = Owl.Data.tag(title, [:bright, :cyan])

    body =
      if Enum.empty?(items) do
        ["\n  ", Owl.Data.tag("(empty)", :faint)]
      else
        Enum.map(items, fn item -> ["\n  ", renderer.(item)] end)
      end

    [header | body]
  end

  defp render_todo(%{"text" => text, "checked" => true}) do
    [Owl.Data.tag("[x] ", :green), Owl.Data.tag(text, :faint)]
  end

  defp render_todo(%{"text" => text}) do
    [Owl.Data.tag("[ ] ", :yellow), text]
  end

  defp render_todo(item) when is_binary(item) do
    ["• ", item]
  end

  defp render_bullet(item) when is_binary(item) do
    ["• ", item]
  end

  defp render_bullet(%{"text" => text}) do
    ["• ", text]
  end

  defp render_bullet(_), do: ""

  defp render_todo_or_bullet(%{"text" => _, "checked" => _} = item), do: render_todo(item)
  defp render_todo_or_bullet(%{"text" => text}), do: ["• ", text]
  defp render_todo_or_bullet(item) when is_binary(item), do: ["• ", item]
  defp render_todo_or_bullet(_), do: ""

  defp to_lines(data) do
    data
    |> Owl.Data.to_chardata()
    |> IO.chardata_to_string()
    |> String.split("\n")
  end

  defp terminal_height do
    case :io.rows() do
      {:ok, rows} -> rows
      _ -> 24
    end
  end
end
