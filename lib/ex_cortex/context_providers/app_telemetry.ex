defmodule ExCortex.ContextProviders.AppTelemetry do
  @moduledoc """
  Injects a structured summary of recent app activity into the prompt.

  Covers: daydream outcomes, circuit breaker trips, LLM errors, deduplicated
  warnings/errors from the Logger. All data comes from the in-process
  AppTelemetry ring buffer — no file reads or shell calls needed.

  Config:
    "window_hours" - how far back to look (default: 6)
    "label"        - section header (default: "## App Telemetry")

  Example:
    %{"type" => "app_telemetry", "window_hours" => 6}
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  @impl true
  def build(config, _thought, _input) do
    window_hours = Map.get(config, "window_hours", 6)
    label = Map.get(config, "label", "## App Telemetry (last #{window_hours}h)")

    summary = ExCortex.AppTelemetry.recent(window_hours: window_hours)

    if summary == "" do
      "#{label}\n\nNo notable activity in the last #{window_hours} hours."
    else
      "#{label}\n\n#{summary}"
    end
  end
end
