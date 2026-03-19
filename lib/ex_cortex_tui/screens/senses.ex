defmodule ExCortexTUI.Screens.Senses do
  @moduledoc "Senses screen: lists active senses with status and type."

  @behaviour ExCortexTUI.Screen

  alias ExCortex.Senses.Reflex
  alias ExCortexTUI.Components.KeyHints
  alias ExCortexTUI.Components.Panel
  alias ExCortexTUI.Components.Status

  @impl true
  def init(_), do: %{}

  @impl true
  def handle_key(_key, state), do: {:noreply, state}

  @impl true
  def render(_state) do
    senses_content = fetch_senses()
    reflexes_content = fetch_reflexes()

    hints =
      KeyHints.render([
        {"c", "Cortex"},
        {"n", "Neurons"},
        {"t", "Thoughts"},
        {"m", "Memory"},
        {"q", "Quit"}
      ])

    Enum.join(
      [Panel.render("Active Senses", senses_content), Panel.render("Reflexes & Streams", reflexes_content), "", hints],
      "\n"
    )
  end

  defp fetch_senses do
    senses = ExCortex.Repo.all(ExCortex.Senses.Sense)

    if Enum.empty?(senses) do
      Status.render(:amber, "No senses configured")
    else
      header =
        "#{String.pad_trailing("NAME", 24)}  #{String.pad_trailing("TYPE", 14)}  STATUS"

      divider = String.duplicate("─", 56)

      rows =
        Enum.map_join(senses, "\n", fn s ->
          name = truncate(s.name || "(unnamed)", 24)
          type = truncate(s.type || "—", 14)
          active = Map.get(s, :active, true)
          color = if active, do: :green, else: :amber
          status_str = Status.render(color, if(active, do: "active", else: "inactive"))

          "#{String.pad_trailing(name, 24)}  #{String.pad_trailing(type, 14)}  #{status_str}"
        end)

      Enum.join([header, divider, rows], "\n")
    end
  rescue
    _ -> Status.render(:red, "Unavailable — DB not connected")
  end

  defp fetch_reflexes do
    reflexes = Reflex.reflexes()
    streams = Reflex.streams()

    reflex_lines =
      if Enum.empty?(reflexes) do
        ["  (no reflexes)"]
      else
        Enum.map(reflexes, fn r ->
          "  " <> Status.render(:cyan, truncate(inspect(r), 54))
        end)
      end

    stream_lines =
      if Enum.empty?(streams) do
        ["  (no streams)"]
      else
        Enum.map(streams, fn s ->
          "  " <> Status.render(:green, truncate(inspect(s), 54))
        end)
      end

    Enum.join(["Reflexes:"] ++ reflex_lines ++ ["", "Streams:"] ++ stream_lines, "\n")
  rescue
    _ -> Status.render(:red, "Unavailable")
  end

  defp truncate(nil, _), do: ""
  defp truncate(s, max) when byte_size(s) <= max, do: s
  defp truncate(s, max), do: String.slice(s, 0, max - 1) <> "…"
end
