# Enable Excessibility telemetry-based auto-capture for debugging
# This is automatically enabled when running: mix excessibility.debug
if System.get_env("EXCESSIBILITY_TELEMETRY_CAPTURE") == "true" do
  Excessibility.TelemetryCapture.attach()
end

ExUnit.start(max_cases: 10)
Ecto.Adapters.SQL.Sandbox.mode(ExCortex.Repo, :manual)
