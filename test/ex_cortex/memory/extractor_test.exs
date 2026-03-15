defmodule ExCortex.Memory.ExtractorTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Memory.Extractor
  alias ExCortex.Ruminations

  setup do
    {:ok, rumination} =
      Ruminations.create_rumination(%{name: "SI Analyst Sweep", trigger: "manual", steps: []})

    {:ok, daydream} =
      Ruminations.create_daydream(%{rumination_id: rumination.id, status: "complete"})

    %{rumination: rumination, daydream: daydream}
  end

  describe "extract/1" do
    test "creates episodic engram from rumination run", %{daydream: daydream} do
      rumination_run = %{
        id: daydream.id,
        rumination_name: "SI Analyst Sweep",
        cluster_name: "Dev Team",
        status: "complete",
        results: %{"summary" => "Found 2 credo issues"},
        impulses: [
          %{step: 1, input: "scan codebase", results: %{"output" => "2 issues"}},
          %{step: 2, input: "file issues", results: %{"output" => "filed #89 #90"}}
        ]
      }

      {:ok, engrams} = Extractor.extract(rumination_run)

      episodic = Enum.find(engrams, &(&1.category == "episodic"))
      assert episodic
      assert episodic.title =~ "SI Analyst Sweep"
      assert episodic.source == "extraction"
      assert episodic.daydream_id == daydream.id
    end

    test "includes impulse summaries in body", %{daydream: daydream} do
      rumination_run = %{
        id: daydream.id,
        rumination_name: "Code Review",
        status: "complete",
        results: %{},
        impulses: [
          %{step: 0, input: "review", results: %{"output" => "looks good"}}
        ]
      }

      {:ok, [engram]} = Extractor.extract(rumination_run)
      assert engram.body =~ "Code Review"
      assert engram.body =~ "looks good"
    end

    test "tags include rumination name slug", %{daydream: daydream} do
      rumination_run = %{
        id: daydream.id,
        rumination_name: "Market Signals",
        status: "complete",
        results: %{},
        impulses: []
      }

      {:ok, [engram]} = Extractor.extract(rumination_run)
      assert "rumination-run" in engram.tags
      assert "market-signals" in engram.tags
    end
  end
end
