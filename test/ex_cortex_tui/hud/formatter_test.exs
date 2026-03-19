defmodule ExCortexTUI.HUD.FormatterTest do
  use ExCortex.DataCase, async: true

  alias ExCortexTUI.HUD.Formatter

  test "formats empty state" do
    output =
      Formatter.format(%{daydreams: [], proposals: [], signals: [], trust_scores: [], errors: []})

    assert output =~ "# hud"
    assert output =~ "## daydreams"
    assert output =~ "(none)"
  end

  test "formats daydream line" do
    daydream = %{
      status: "running",
      rumination: %{name: "solar-digest", steps: [%{}, %{}, %{}, %{}, %{}]},
      synapse_results: %{"step1" => %{}, "step2" => %{}},
      inserted_at: DateTime.add(DateTime.utc_now(), -120)
    }

    line = Formatter.format_daydream(daydream)
    assert line =~ "running"
    assert line =~ "solar-digest"
    assert line =~ "2/5 impulses"
  end

  test "formats proposal line" do
    proposal = %{
      status: "pending",
      description: "trust-bump analyst",
      type: "roster_change",
      details: %{"confidence" => 0.82},
      inserted_at: DateTime.add(DateTime.utc_now(), -3600)
    }

    line = Formatter.format_proposal(proposal)
    assert line =~ "pending"
    assert line =~ "trust-bump analyst"
    assert line =~ "confidence=0.82"
  end

  test "formats trust scores" do
    scores = [%{neuron_name: "analyst", score: 0.94}, %{neuron_name: "qa", score: 0.91}]
    line = Formatter.format_trust(scores)
    assert line =~ "analyst=0.94"
    assert line =~ "qa=0.91"
  end

  test "formats signal line" do
    signal = %{
      source: "sense:github",
      title: "new issue #42",
      inserted_at: DateTime.add(DateTime.utc_now(), -120)
    }

    line = Formatter.format_signal(signal)
    assert line =~ "sense:github"
    assert line =~ "new issue #42"
  end

  test "formats error line" do
    error = %{message: "LLM timeout", source: "impulse_runner"}
    line = Formatter.format_error(error)
    assert line =~ "LLM timeout"
    assert line =~ "impulse_runner"
  end

  test "full format includes all sections" do
    state = %{
      daydreams: [
        %{
          status: "running",
          rumination: %{name: "test-run", steps: [%{}, %{}]},
          synapse_results: %{"s1" => %{}},
          inserted_at: DateTime.add(DateTime.utc_now(), -60)
        }
      ],
      proposals: [
        %{
          status: "pending",
          description: "bump qa",
          type: "roster_change",
          details: %{"confidence" => 0.9},
          inserted_at: DateTime.add(DateTime.utc_now(), -300)
        }
      ],
      signals: [
        %{source: "sense:feed", title: "new article", inserted_at: DateTime.utc_now()}
      ],
      trust_scores: [%{neuron_name: "analyst", score: 0.95}],
      errors: []
    }

    output = Formatter.format(state)
    assert output =~ "# hud"
    assert output =~ "## daydreams"
    assert output =~ "running"
    assert output =~ "## proposals"
    assert output =~ "pending"
    assert output =~ "## signals"
    assert output =~ "sense:feed"
    assert output =~ "## trust"
    assert output =~ "analyst=0.95"
    assert output =~ "## errors"
    assert output =~ "(none)"
  end
end
