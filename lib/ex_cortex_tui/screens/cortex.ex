defmodule ExCortexTUI.Screens.Cortex do
  @moduledoc "Dashboard screen: Active Ruminations, Recent Signals, Cluster Health, Recent Memory."

  @behaviour ExCortexTUI.Screen

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "signals")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "memory")
    Map.put(fetch_all(), :scroll, 0)
  end

  @impl true
  def render(state) do
    # Render all panels into lines, then apply scroll offset
    lines =
      state
      |> render_all_panels()
      |> Owl.Data.to_chardata()
      |> IO.chardata_to_string()
      |> String.split("\n")

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
  def handle_key(_key, state), do: {:noreply, state}

  @impl true
  def handle_info(_msg, state), do: {:noreply, Map.put(fetch_all(), :scroll, state.scroll)}

  # -- Panels --

  defp render_all_panels(state) do
    [
      Owl.Box.new(render_ruminations(state.ruminations), title: "Active Ruminations", min_width: 60),
      "\n",
      Owl.Box.new(render_signals(state.signals), title: "Recent Signals", min_width: 60),
      "\n",
      Owl.Box.new(render_clusters(state.clusters), title: "Cluster Health", min_width: 60),
      "\n",
      Owl.Box.new(render_memory(state.engrams), title: "Recent Memory", min_width: 60)
    ]
  end

  # -- Data fetching --

  defp fetch_all do
    %{
      ruminations: safe_fetch(fn -> Enum.take(ExCortex.Ruminations.list_ruminations(), 5) end),
      signals: safe_fetch(fn -> ExCortex.Signals.list_signals(limit: 5) end),
      clusters: safe_fetch(fn -> Enum.take(ExCortex.Clusters.list_pathways(), 5) end),
      engrams: safe_fetch(fn -> ExCortex.Memory.list_engrams(limit: 5) end)
    }
  end

  defp safe_fetch(fun) do
    fun.()
  rescue
    _ -> []
  end

  # -- Rendering --

  defp render_ruminations([]), do: Owl.Data.tag("No active ruminations", :yellow)

  defp render_ruminations(ruminations) do
    ruminations
    |> Enum.take(5)
    |> Enum.map_intersperse("\n", fn t ->
      color = rumination_color(t.status)
      [Owl.Data.tag("● ", color), "#{t.name}  ", Owl.Data.tag("[#{t.status}]", color)]
    end)
  end

  defp render_signals([]), do: Owl.Data.tag("No recent signals", :yellow)

  defp render_signals(signals) do
    Enum.map_intersperse(signals, "\n", fn s ->
      source = s.source || s.type || "?"
      title = truncate(s.title || s.body || "", 40)
      [Owl.Data.tag(format_time(s.inserted_at), :faint), "  ", Owl.Data.tag(source, :cyan), "  ", title]
    end)
  end

  defp render_clusters([]), do: Owl.Data.tag("No clusters installed", :yellow)

  defp render_clusters(clusters) do
    Enum.map_intersperse(clusters, "\n", fn c ->
      name = Map.get(c, :cluster_name) || Map.get(c, :name) || "?"
      [Owl.Data.tag("● ", :green), name, "  ", Owl.Data.tag(truncate(c.pathway_text || "", 50), :faint)]
    end)
  end

  defp render_memory([]), do: Owl.Data.tag("No engrams stored", :yellow)

  defp render_memory(engrams) do
    Enum.map_intersperse(engrams, "\n", fn e ->
      importance = String.duplicate("★", min(e.importance || 1, 5))
      [Owl.Data.tag(importance, :yellow), "  #{truncate(e.title, 44)}  ", Owl.Data.tag("[#{e.category}]", :faint)]
    end)
  end

  defp rumination_color("active"), do: :green
  defp rumination_color("running"), do: :cyan
  defp rumination_color("failed"), do: :red
  defp rumination_color(_), do: :yellow

  defp truncate(nil, _max), do: ""
  defp truncate(s, max) when byte_size(s) <= max, do: s
  defp truncate(s, max), do: String.slice(s, 0, max - 1) <> "…"

  defp format_time(%NaiveDateTime{} = dt), do: dt |> NaiveDateTime.to_string() |> String.slice(0, 16)
  defp format_time(%DateTime{} = dt), do: dt |> DateTime.to_string() |> String.slice(0, 16)
  defp format_time(_), do: "??:??"

  defp terminal_height do
    case :io.columns() do
      {:ok, _cols} ->
        case :io.rows() do
          {:ok, rows} -> rows
          _ -> 24
        end

      _ ->
        24
    end
  end
end
