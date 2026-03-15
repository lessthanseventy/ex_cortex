defmodule ExCortex.Thoughts.Runner.VerdictGateTest do
  use ExUnit.Case, async: true

  alias ExCortex.Thoughts.Runner

  describe "check_gate/2" do
    test "no gate field passes through" do
      step_entry = %{"step_id" => "1", "order" => 1}
      result = {:ok, %{verdict: "fail", steps: []}}
      assert :continue = Runner.check_gate(step_entry, result)
    end

    test "gate true with pass verdict continues" do
      step_entry = %{"step_id" => "1", "order" => 1, "gate" => true}
      result = {:ok, %{verdict: "pass", steps: []}}
      assert :continue = Runner.check_gate(step_entry, result)
    end

    test "gate true with fail verdict blocks" do
      step_entry = %{"step_id" => "1", "order" => 1, "gate" => true}
      result = {:ok, %{verdict: "fail", steps: [%{results: [%{reason: "tests broken"}]}]}}
      assert {:gated, _reason} = Runner.check_gate(step_entry, result)
    end

    test "gate true with fail extracts reason from nested results" do
      step_entry = %{"step_id" => "1", "order" => 1, "gate" => true}

      result =
        {:ok,
         %{
           verdict: "fail",
           steps: [
             %{results: [%{reason: "lint failed"}, %{reason: "type errors"}]},
             %{results: [%{reason: "coverage low"}]}
           ]
         }}

      assert {:gated, reason} = Runner.check_gate(step_entry, result)
      assert reason =~ "lint failed"
      assert reason =~ "type errors"
      assert reason =~ "coverage low"
    end

    test "gate true with abstain continues" do
      step_entry = %{"step_id" => "1", "order" => 1, "gate" => true}
      result = {:ok, %{verdict: "abstain", steps: []}}
      assert :continue = Runner.check_gate(step_entry, result)
    end

    test "gate true with error result continues" do
      step_entry = %{"step_id" => "1", "order" => 1, "gate" => true}
      result = {:error, :something}
      assert :continue = Runner.check_gate(step_entry, result)
    end

    test "gate false with fail verdict continues" do
      step_entry = %{"step_id" => "1", "order" => 1, "gate" => false}
      result = {:ok, %{verdict: "fail", steps: []}}
      assert :continue = Runner.check_gate(step_entry, result)
    end
  end
end
