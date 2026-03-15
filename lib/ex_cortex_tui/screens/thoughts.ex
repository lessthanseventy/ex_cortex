defmodule ExCortexTUI.Screens.Thoughts do
  @moduledoc "Thoughts screen: lists ruminations with status, trigger, and synapse count."

  alias ExCortexTUI.Components.KeyHints
  alias ExCortexTUI.Components.Panel
  alias ExCortexTUI.Components.Status

  def render(_state) do
    content = fetch_ruminations()

    hints =
      KeyHints.render([
        {"c", "Cortex"},
        {"n", "Neurons"},
        {"m", "Memory"},
        {"s", "Senses"},
        {"q", "Quit"}
      ])

    Enum.join([Panel.render("Ruminations", content), "", hints], "\n")
  end

  defp fetch_ruminations do
    ruminations = ExCortex.Ruminations.list_ruminations()

    if Enum.empty?(ruminations) do
      Status.render(:amber, "No ruminations defined")
    else
      header = pad_row("NAME", "STATUS", "TRIGGER", "SYNAPSES")
      divider = String.duplicate("─", 56)

      rows =
        Enum.map_join(ruminations, "\n", fn t ->
          synapses =
            try do
              (t.steps || []) |> length() |> Integer.to_string()
            rescue
              _ -> "?"
            end

          color = status_color(t.status)
          status_str = Status.render(color, t.status)
          trigger = truncate(Map.get(t, :trigger_type, "manual"), 14)
          name = truncate(t.name, 22)

          # Plain version for padding (strip ANSI from status for alignment)
          prefix_status(
            "#{String.pad_trailing(name, 22)}  #{String.pad_trailing(t.status, 10)}  #{String.pad_trailing(trigger, 14)}  #{synapses}",
            status_str,
            t.status
          )
        end)

      Enum.join([header, divider, rows], "\n")
    end
  rescue
    _ -> Status.render(:red, "Unavailable — DB not connected")
  end

  # Replace the plain status text with a colored version in the rendered row
  defp prefix_status(row, status_str, plain_status) do
    String.replace(row, plain_status, status_str, global: false)
  end

  defp pad_row(name, status, trigger, synapses) do
    "#{String.pad_trailing(name, 22)}  #{String.pad_trailing(status, 10)}  #{String.pad_trailing(trigger, 14)}  #{synapses}"
  end

  defp status_color("active"), do: :green
  defp status_color("running"), do: :cyan
  defp status_color("failed"), do: :red
  defp status_color(_), do: :amber

  defp truncate(nil, _), do: ""
  defp truncate(s, max) when byte_size(s) <= max, do: s
  defp truncate(s, max), do: String.slice(s, 0, max - 1) <> "…"
end
