defmodule ExCortexTUI.Screens.Cortex do
  @moduledoc "Dashboard screen: Active Thoughts, Recent Signals, Cluster Health, Recent Memory."

  alias ExCortexTUI.Components.KeyHints
  alias ExCortexTUI.Components.Panel
  alias ExCortexTUI.Components.Status

  def render(_state) do
    thoughts_content = fetch_thoughts()
    signals_content = fetch_signals()
    clusters_content = fetch_clusters()
    memory_content = fetch_memory()

    hints =
      KeyHints.render([
        {"c", "Cortex"},
        {"n", "Neurons"},
        {"t", "Thoughts"},
        {"m", "Memory"},
        {"s", "Senses"},
        {"i", "Instinct"},
        {"g", "Guide"},
        {"q", "Quit"}
      ])

    Enum.join(
      [
        Panel.render("Active Thoughts", thoughts_content),
        Panel.render("Recent Signals", signals_content),
        Panel.render("Cluster Health", clusters_content),
        Panel.render("Recent Memory", memory_content),
        "",
        hints
      ],
      "\n"
    )
  end

  defp fetch_thoughts do
    thoughts = ExCortex.Thoughts.list_thoughts()

    if Enum.empty?(thoughts) do
      Status.render(:amber, "No active thoughts")
    else
      thoughts
      |> Enum.take(5)
      |> Enum.map_join("\n", fn t ->
        color = thought_color(t.status)
        Status.render(color, "#{t.name}  [#{t.status}]")
      end)
    end
  rescue
    _ -> Status.render(:red, "Unavailable — DB not connected")
  end

  defp fetch_signals do
    signals = ExCortex.Signals.list_signals(limit: 5)

    if Enum.empty?(signals) do
      Status.render(:amber, "No recent signals")
    else
      Enum.map_join(signals, "\n", fn s ->
        "#{format_time(s.inserted_at)}  #{s.source_type}  #{truncate(s.content, 40)}"
      end)
    end
  rescue
    _ -> Status.render(:red, "Unavailable — DB not connected")
  end

  defp fetch_clusters do
    clusters = ExCortex.Clusters.list_pathways()

    if Enum.empty?(clusters) do
      Status.render(:amber, "No clusters installed")
    else
      Enum.map_join(clusters, "\n", fn c ->
        neuron_count = length(Map.get(c, :neurons, []))
        Status.render(:green, "#{c.name}  (#{neuron_count} neurons)")
      end)
    end
  rescue
    _ -> Status.render(:red, "Unavailable — DB not connected")
  end

  defp fetch_memory do
    engrams = ExCortex.Memory.list_engrams(limit: 5)

    if Enum.empty?(engrams) do
      Status.render(:amber, "No engrams stored")
    else
      Enum.map_join(engrams, "\n", fn e ->
        importance = String.duplicate("★", min(e.importance || 1, 5))
        "#{importance}  #{truncate(e.title, 44)}  [#{e.category}]"
      end)
    end
  rescue
    _ -> Status.render(:red, "Unavailable — DB not connected")
  end

  defp thought_color("active"), do: :green
  defp thought_color("running"), do: :cyan
  defp thought_color("failed"), do: :red
  defp thought_color(_), do: :amber

  defp truncate(nil, _), do: ""
  defp truncate(s, max) when byte_size(s) <= max, do: s
  defp truncate(s, max), do: String.slice(s, 0, max - 1) <> "…"

  defp format_time(%NaiveDateTime{} = dt), do: dt |> NaiveDateTime.to_string() |> String.slice(0, 16)
  defp format_time(%DateTime{} = dt), do: dt |> DateTime.to_string() |> String.slice(0, 16)
  defp format_time(_), do: "??:??"
end
