defmodule ExCortexTUI.Screens.Instinct do
  @moduledoc "Instinct screen: shows current app settings — Ollama URL, API keys, banner."

  alias ExCortexTUI.Components.KeyHints
  alias ExCortexTUI.Components.Panel
  alias ExCortexTUI.Components.Status

  def render(_state) do
    settings_content = fetch_settings()
    expressions_content = fetch_expressions()

    hints =
      KeyHints.render([
        {"c", "Cortex"},
        {"n", "Neurons"},
        {"t", "Thoughts"},
        {"g", "Guide"},
        {"q", "Quit"}
      ])

    Enum.join(
      [
        Panel.render("Settings", settings_content),
        Panel.render("Expressions (Expressions)", expressions_content),
        "",
        hints
      ],
      "\n"
    )
  end

  defp fetch_settings do
    ollama_url = ExCortex.Settings.get(:ollama_url) || "(not set)"
    banner = ExCortex.Settings.get_banner() || "(no banner)"
    anthropic_key = ExCortex.Settings.get(:anthropic_api_key)
    openai_key = ExCortex.Settings.get(:openai_api_key)

    anthropic_status =
      if present?(anthropic_key),
        do: Status.render(:green, "present"),
        else: Status.render(:amber, "not set")

    openai_status =
      if present?(openai_key),
        do: Status.render(:green, "present"),
        else: Status.render(:amber, "not set")

    Enum.join(
      [
        "Ollama URL:       #{ollama_url}",
        "Anthropic Key:    #{anthropic_status}",
        "OpenAI Key:       #{openai_status}",
        "",
        "Banner:",
        "  #{banner}"
      ],
      "\n"
    )
  rescue
    _ -> Status.render(:red, "Unavailable — DB not connected")
  end

  defp fetch_expressions do
    expressions = ExCortex.Expressions.list_expressions()

    if Enum.empty?(expressions) do
      Status.render(:amber, "No expressions configured")
    else
      Enum.map_join(expressions, "\n", fn h ->
        type = truncate(Map.get(h, :type, "unknown"), 14)
        name = truncate(h.name || "(unnamed)", 36)
        Status.render(:cyan, "#{String.pad_trailing(name, 36)}  [#{type}]")
      end)
    end
  rescue
    _ -> Status.render(:amber, "Expressions unavailable")
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  defp truncate(nil, _), do: ""
  defp truncate(s, max) when byte_size(s) <= max, do: s
  defp truncate(s, max), do: String.slice(s, 0, max - 1) <> "…"
end
