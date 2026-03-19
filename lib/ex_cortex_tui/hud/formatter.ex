defmodule ExCortexTUI.HUD.Formatter do
  @moduledoc """
  Formats system state into plain, machine-readable text for AI consumption.
  No ANSI colors, no box-drawing — just structured text with ## section headers.
  """

  @doc "Format full HUD state map into a multi-line string."
  def format(state) do
    timestamp = DateTime.to_iso8601(DateTime.utc_now())

    [
      "# hud #{timestamp}",
      "",
      "## daydreams",
      format_section(state.daydreams, &format_daydream/1),
      "",
      "## proposals",
      format_section(state.proposals, &format_proposal/1),
      "",
      "## signals",
      format_section(state.signals, &format_signal/1),
      "",
      "## trust",
      format_trust(state.trust_scores),
      "",
      "## errors",
      format_section(state.errors, &format_error/1)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  @doc "Format a single daydream into a one-line summary."
  def format_daydream(d) do
    name = truncate(d.rumination.name, 25)
    completed = map_size(d.synapse_results || %{})
    total = length(d.rumination[:steps] || d.rumination.steps)
    age = relative_time(d.inserted_at)

    pad(d.status, 10) <> pad(name, 27) <> "#{completed}/#{total} impulses  #{age}"
  end

  @doc "Format a single proposal into a one-line summary."
  def format_proposal(p) do
    desc = truncate(p.description, 30)
    confidence = get_in(p.details, ["confidence"]) || get_in(p.details, [:confidence])
    age = relative_time(p.inserted_at)

    conf_str = if confidence, do: "confidence=#{confidence}", else: "type=#{p.type}"

    pad(p.status, 10) <> pad(desc, 32) <> pad(conf_str, 18) <> "submitted=#{age}"
  end

  @doc "Format a single signal into a one-line summary."
  def format_signal(s) do
    age = relative_time(s.inserted_at)
    source = truncate(s.source || "unknown", 18)
    title = truncate(s.title || "", 50)

    pad(age, 10) <> pad(source, 20) <> title
  end

  @doc "Format trust scores as a single line of name=score pairs."
  def format_trust([]), do: "(none)"

  def format_trust(scores) do
    Enum.map_join(scores, "  ", fn s -> "#{s.neuron_name}=#{s.score}" end)
  end

  @doc "Format a single error into a one-line summary."
  def format_error(e) do
    source = truncate(Map.get(e, :source, "unknown"), 20)
    message = truncate(Map.get(e, :message, ""), 60)

    pad(source, 22) <> message
  end

  # --- Private helpers ---

  defp format_section([], _formatter), do: "(none)"

  defp format_section(items, formatter) do
    Enum.map(items, formatter)
  end

  defp relative_time(nil), do: "?"

  defp relative_time(dt) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max - 1) <> "~"

  defp pad(str, width) do
    String.pad_trailing(str, width)
  end
end
