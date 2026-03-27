defmodule ExCortex.Ruminations.Middleware.ThreatGateTest do
  use ExUnit.Case, async: true

  alias ExCortex.Ruminations.Middleware.Context
  alias ExCortex.Ruminations.Middleware.ThreatGate
  alias ExCortex.Security.ThreatTracker

  setup do
    start_supervised!(ThreatTracker)
    :ok
  end

  describe "before_impulse/2" do
    test "allows when score below threshold" do
      ctx = %Context{
        input_text: "safe input",
        metadata: %{},
        daydream: %{id: 100}
      }

      assert {:cont, ^ctx} = ThreatGate.before_impulse(ctx, [])
    end

    test "halts when score at halt threshold" do
      ThreatTracker.increment(101, 10.0)

      ctx = %Context{
        input_text: "suspicious input",
        metadata: %{},
        daydream: %{id: 101}
      }

      assert {:halt, :threat_threshold_exceeded} = ThreatGate.before_impulse(ctx, [])
    end

    test "allows but warns at warn threshold" do
      ThreatTracker.increment(102, 5.0)

      ctx = %Context{
        input_text: "borderline input",
        metadata: %{},
        daydream: %{id: 102}
      }

      assert {:cont, _} = ThreatGate.before_impulse(ctx, [])
    end

    test "handles missing daydream gracefully" do
      ctx = %Context{input_text: "test", metadata: %{}, daydream: nil}
      assert {:cont, ^ctx} = ThreatGate.before_impulse(ctx, [])
    end
  end
end
