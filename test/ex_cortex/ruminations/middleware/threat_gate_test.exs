defmodule ExCortex.Ruminations.Middleware.ThreatGateTest do
  use ExUnit.Case, async: false

  alias ExCortex.Ruminations.Middleware.Context
  alias ExCortex.Ruminations.Middleware.ThreatGate
  alias ExCortex.Security.ThreatTracker

  # ThreatTracker starts in application.ex base_children

  setup do
    id = System.unique_integer([:positive])
    on_exit(fn -> ThreatTracker.clear(id) end)
    %{id: id}
  end

  describe "before_impulse/2" do
    test "allows when score below threshold", %{id: id} do
      ctx = %Context{
        input_text: "safe input",
        metadata: %{},
        daydream: %{id: id}
      }

      assert {:cont, ^ctx} = ThreatGate.before_impulse(ctx, [])
    end

    test "halts when score at halt threshold", %{id: id} do
      ThreatTracker.increment(id, 10.0)

      ctx = %Context{
        input_text: "suspicious input",
        metadata: %{},
        daydream: %{id: id}
      }

      assert {:halt, :threat_threshold_exceeded} = ThreatGate.before_impulse(ctx, [])
    end

    test "allows but warns at warn threshold", %{id: id} do
      ThreatTracker.increment(id, 5.0)

      ctx = %Context{
        input_text: "borderline input",
        metadata: %{},
        daydream: %{id: id}
      }

      assert {:cont, _} = ThreatGate.before_impulse(ctx, [])
    end

    test "handles missing daydream gracefully" do
      ctx = %Context{input_text: "test", metadata: %{}, daydream: nil}
      assert {:cont, ^ctx} = ThreatGate.before_impulse(ctx, [])
    end
  end
end
