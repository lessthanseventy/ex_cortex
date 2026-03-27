defmodule ExCortex.Ruminations.RosterResolverTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo
  alias ExCortex.Ruminations.RosterResolver

  defp insert_neuron!(attrs) do
    %Neuron{}
    |> Neuron.changeset(
      Map.merge(
        %{type: "role", status: "active", source: "db"},
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "resolve/1 with 'all'" do
    test "returns all active role neurons" do
      n1 = insert_neuron!(%{name: "Alpha", config: %{"provider" => "ollama", "model" => "m1"}})
      n2 = insert_neuron!(%{name: "Beta", config: %{"provider" => "ollama", "model" => "m2"}})
      _draft = insert_neuron!(%{name: "Draft", status: "draft", config: %{}})

      result = RosterResolver.resolve("all")
      names = Enum.map(result, & &1.name)

      assert n1.name in names
      assert n2.name in names
      refute "Draft" in names
    end

    test "returns empty list when no active role neurons exist" do
      insert_neuron!(%{name: "Archived", status: "archived", config: %{}})
      result = RosterResolver.resolve("all")
      refute Enum.any?(result, &(&1.name == "Archived"))
    end
  end

  describe "resolve/1 with rank strings" do
    test "resolves apprentice rank" do
      insert_neuron!(%{name: "Junior", config: %{"rank" => "apprentice", "model" => "m1"}})
      insert_neuron!(%{name: "Senior", config: %{"rank" => "master", "model" => "m2"}})

      result = RosterResolver.resolve("apprentice")
      names = Enum.map(result, & &1.name)

      assert "Junior" in names
      refute "Senior" in names
    end

    test "resolves journeyman rank" do
      insert_neuron!(%{name: "Mid", config: %{"rank" => "journeyman", "model" => "m1"}})

      result = RosterResolver.resolve("journeyman")
      assert [%{name: "Mid"}] = result
    end

    test "resolves master rank" do
      insert_neuron!(%{name: "Expert", config: %{"rank" => "master", "model" => "m1"}})

      result = RosterResolver.resolve("master")
      assert [%{name: "Expert"}] = result
    end
  end

  describe "resolve/1 with team" do
    test "resolves team:X pattern" do
      insert_neuron!(%{name: "TeamA1", team: "alpha", config: %{"model" => "m1"}})
      insert_neuron!(%{name: "TeamB1", team: "bravo", config: %{"model" => "m2"}})

      result = RosterResolver.resolve("team:alpha")
      names = Enum.map(result, & &1.name)

      assert "TeamA1" in names
      refute "TeamB1" in names
    end

    test "returns empty for nonexistent team" do
      assert [] = RosterResolver.resolve("team:nonexistent")
    end
  end

  describe "resolve/1 with challenger" do
    test "returns a challenger spec from builtins" do
      result = RosterResolver.resolve("challenger")
      assert [%{name: "Challenger", provider: "ollama"}] = result
    end
  end

  describe "resolve/1 with claude tiers" do
    test "resolves claude_haiku inline" do
      assert [%{provider: "claude", model: "claude_haiku", name: "claude_haiku"}] =
               RosterResolver.resolve("claude_haiku")
    end

    test "resolves claude_sonnet inline" do
      assert [%{provider: "claude", model: "claude_sonnet"}] =
               RosterResolver.resolve("claude_sonnet")
    end

    test "resolves claude_opus inline" do
      assert [%{provider: "claude", model: "claude_opus"}] =
               RosterResolver.resolve("claude_opus")
    end
  end

  describe "resolve/1 with neuron ID" do
    test "resolves a bare neuron ID" do
      neuron = insert_neuron!(%{name: "Direct", config: %{"provider" => "ollama", "model" => "m1"}})

      result = RosterResolver.resolve(to_string(neuron.id))
      assert [%{name: "Direct", provider: "ollama", model: "m1"}] = result
    end

    test "returns empty for nonexistent ID" do
      assert [] = RosterResolver.resolve("999999")
    end
  end

  describe "resolve/1 with preferred_who" do
    test "preferred_who with rank filters by both name and rank" do
      insert_neuron!(%{name: "Analyst", config: %{"rank" => "journeyman", "model" => "m1"}})
      insert_neuron!(%{name: "Analyst", config: %{"rank" => "master", "model" => "m2"}})

      result = RosterResolver.resolve(%{"preferred_who" => "Analyst", "who" => "journeyman"})
      assert [%{name: "Analyst", model: "m1"}] = result
    end

    test "preferred_who without rank returns all matching names" do
      insert_neuron!(%{name: "Analyst", config: %{"rank" => "journeyman", "model" => "m1"}})
      insert_neuron!(%{name: "Analyst", config: %{"rank" => "master", "model" => "m2"}})

      result = RosterResolver.resolve(%{"preferred_who" => "Analyst", "who" => "all"})
      assert length(result) == 2
      assert Enum.all?(result, &(&1.name == "Analyst"))
    end

    test "preferred_who falls back when name not found" do
      insert_neuron!(%{name: "Other", config: %{"rank" => "journeyman", "model" => "m1"}})

      result = RosterResolver.resolve(%{"preferred_who" => "NonExistent", "who" => "journeyman"})
      # Falls back to rank-based resolution
      assert [%{name: "Other"}] = result
    end
  end

  describe "resolve/1 with map step" do
    test "extracts who key from step map" do
      result = RosterResolver.resolve(%{"who" => "claude_haiku", "how" => "solo"})
      assert [%{provider: "claude", model: "claude_haiku"}] = result
    end

    test "defaults to 'all' when who key is missing" do
      insert_neuron!(%{name: "Default", config: %{"model" => "m1"}})

      result = RosterResolver.resolve(%{"how" => "solo"})
      names = Enum.map(result, & &1.name)
      assert "Default" in names
    end
  end

  describe "resolve/1 neuron spec shape" do
    test "includes all required keys" do
      insert_neuron!(%{name: "Shape", config: %{"provider" => "ollama", "model" => "m1", "system_prompt" => "test"}})

      [spec] = RosterResolver.resolve(%{"who" => "all"})
      assert Map.has_key?(spec, :provider)
      assert Map.has_key?(spec, :model)
      assert Map.has_key?(spec, :system_prompt)
      assert Map.has_key?(spec, :name)
      assert Map.has_key?(spec, :tools)
    end

    test "defaults provider to ollama and model to phi4-mini" do
      insert_neuron!(%{name: "Minimal", config: %{}})

      [spec] = RosterResolver.resolve(%{"who" => "all"})
      assert spec.provider == "ollama"
      assert spec.model == "phi4-mini"
    end
  end

  describe "resolve_roster/1" do
    test "resolves a full roster with when and how" do
      insert_neuron!(%{name: "R1", config: %{"model" => "m1"}})

      roster = [
        %{"who" => "all", "when" => "sequential", "how" => "consensus"},
        %{"who" => "claude_haiku", "when" => "parallel", "how" => "solo"}
      ]

      result = RosterResolver.resolve_roster(roster)

      assert [first, second] = result
      assert first.when == "sequential"
      assert first.how == "consensus"
      assert first.neurons != []

      assert second.when == "parallel"
      assert second.how == "solo"
      assert [%{provider: "claude"}] = second.neurons
    end

    test "defaults when to parallel and how to solo" do
      roster = [%{"who" => "claude_opus"}]

      [entry] = RosterResolver.resolve_roster(roster)
      assert entry.when == "parallel"
      assert entry.how == "solo"
    end
  end
end
