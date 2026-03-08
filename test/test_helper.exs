# Enable Excessibility telemetry-based auto-capture for debugging
# This is automatically enabled when running: mix excessibility.debug
if System.get_env("EXCESSIBILITY_TELEMETRY_CAPTURE") == "true" do
  Excessibility.TelemetryCapture.attach()
end

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(ExCellenceServer.Repo, :manual)
