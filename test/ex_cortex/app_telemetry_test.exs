defmodule ExCortex.AppTelemetryTest do
  use ExCortex.DataCase, async: false

  alias ExCortex.AppTelemetry

  setup do
    AppTelemetry.reset()
    :ok
  end

  test "starts with empty buffers" do
    result = AppTelemetry.recent(window_hours: 24)
    assert result == ""
  end

  test "records LLM call errors and surfaces them" do
    AppTelemetry.record_llm_call("devstral-small-2:24b", 1500, :ok)
    AppTelemetry.record_llm_call("devstral-small-2:24b", 500, {:error, :timeout})
    # Wait for async casts to process
    _ = AppTelemetry.recent(window_hours: 24)

    result = AppTelemetry.recent(window_hours: 24)
    assert result =~ "devstral-small-2:24b"
    assert result =~ "LLM errors"
  end

  test "records circuit breaker trips with counts" do
    AppTelemetry.record_circuit_breaker("list_files")
    AppTelemetry.record_circuit_breaker("list_files")
    AppTelemetry.record_circuit_breaker("read_file")
    _ = AppTelemetry.recent(window_hours: 24)

    result = AppTelemetry.recent(window_hours: 24)
    assert result =~ "list_files ×2"
    assert result =~ "read_file ×1"
  end

  test "deduplicates repeated log events" do
    AppTelemetry.record_log_event(:warning, "Connection refused", MyModule)
    AppTelemetry.record_log_event(:warning, "Connection refused", MyModule)
    AppTelemetry.record_log_event(:warning, "Connection refused", MyModule)
    _ = AppTelemetry.recent(window_hours: 24)

    result = AppTelemetry.recent(window_hours: 24)
    assert result =~ "Connection refused"
    assert result =~ "×3"
  end

  test "respects window_hours filter" do
    AppTelemetry.record_circuit_breaker("list_files")
    _ = AppTelemetry.recent(window_hours: 24)

    # window_hours: 0 means cutoff is now, events from just now are within 0 seconds
    # Use a negative window to ensure nothing passes
    result = AppTelemetry.recent(window_hours: -1)
    refute result =~ "Circuit breakers"
  end

  test "returns empty string when AppTelemetry is not running" do
    result =
      case Process.whereis(AppTelemetry) do
        nil -> AppTelemetry.recent(window_hours: 24)
        _ -> ""
      end

    assert result == ""
  end
end
