defmodule ExCortex.Muse.ClassifierTest do
  use ExUnit.Case, async: true

  alias ExCortex.Muse.Classifier

  describe "parse_result/1" do
    test "parses valid JSON" do
      json =
        ~s|{"providers": ["obsidian", "engrams"], "time_range": "week", "obsidian_mode": "daily", "obsidian_sections": ["brain_dump"], "search_terms": "brain dump"}|

      assert {:ok, result} = Classifier.parse_result(json)
      assert result.providers == ["obsidian", "engrams"]
      assert result.time_range == "week"
      assert result.obsidian_mode == "daily"
      assert result.obsidian_sections == ["brain_dump"]
      assert result.search_terms == "brain dump"
    end

    test "parses JSON wrapped in markdown code block" do
      json = """
      ```json
      {"providers": ["obsidian"], "time_range": "today", "obsidian_mode": "daily", "obsidian_sections": ["all"], "search_terms": ""}
      ```
      """

      assert {:ok, result} = Classifier.parse_result(json)
      assert result.providers == ["obsidian"]
      assert result.time_range == "today"
    end

    test "returns default on invalid JSON" do
      assert {:error, :invalid_json} = Classifier.parse_result("not json at all")
    end

    test "filters out unknown provider names" do
      json =
        ~s|{"providers": ["obsidian", "bogus", "engrams", "fake"], "time_range": "all", "obsidian_mode": "auto", "obsidian_sections": ["all"], "search_terms": ""}|

      assert {:ok, result} = Classifier.parse_result(json)
      assert result.providers == ["obsidian", "engrams"]
    end

    test "defaults invalid time_range to all" do
      json =
        ~s|{"providers": ["obsidian"], "time_range": "fortnight", "obsidian_mode": "auto", "obsidian_sections": ["all"], "search_terms": ""}|

      assert {:ok, result} = Classifier.parse_result(json)
      assert result.time_range == "all"
    end

    test "defaults invalid obsidian_mode to auto" do
      json =
        ~s|{"providers": ["obsidian"], "time_range": "week", "obsidian_mode": "invalid", "obsidian_sections": ["all"], "search_terms": ""}|

      assert {:ok, result} = Classifier.parse_result(json)
      assert result.obsidian_mode == "auto"
    end

    test "filters out invalid obsidian_sections" do
      json =
        ~s|{"providers": ["obsidian"], "time_range": "week", "obsidian_mode": "daily", "obsidian_sections": ["brain_dump", "invalid_section"], "search_terms": ""}|

      assert {:ok, result} = Classifier.parse_result(json)
      assert result.obsidian_sections == ["brain_dump"]
    end
  end

  describe "default_classification/0" do
    test "includes core providers" do
      result = Classifier.default_classification()
      assert "obsidian" in result.providers
      assert "engrams" in result.providers
      assert "signals" in result.providers
    end

    test "uses safe defaults" do
      result = Classifier.default_classification()
      assert result.time_range == "all"
      assert result.obsidian_mode == "auto"
      assert result.obsidian_sections == ["all"]
      assert result.search_terms == ""
    end
  end

  describe "build_providers_from_classification/1" do
    test "always includes sources and engrams" do
      classification = %{
        providers: ["signals"],
        time_range: "all",
        obsidian_mode: "auto",
        obsidian_sections: ["all"],
        search_terms: ""
      }

      providers = Classifier.build_providers_from_classification(classification)
      types = Enum.map(providers, & &1["type"])
      assert "sources" in types
      assert "engrams" in types
    end

    test "builds obsidian daily_range with time_range and sections" do
      classification = %{
        providers: ["obsidian"],
        time_range: "week",
        obsidian_mode: "daily",
        obsidian_sections: ["brain_dump"],
        search_terms: ""
      }

      providers = Classifier.build_providers_from_classification(classification)

      obsidian = Enum.find(providers, &(&1["type"] == "obsidian"))
      assert obsidian["mode"] == "daily_range"
      assert obsidian["time_range"] == "week"
      assert obsidian["sections"] == ["brain_dump"]
    end

    test "builds obsidian daily mode when time_range is today and sections is all" do
      classification = %{
        providers: ["obsidian"],
        time_range: "today",
        obsidian_mode: "daily",
        obsidian_sections: ["all"],
        search_terms: ""
      }

      providers = Classifier.build_providers_from_classification(classification)

      obsidian = Enum.find(providers, &(&1["type"] == "obsidian"))
      assert obsidian["mode"] == "auto"
    end

    test "builds search mode correctly" do
      classification = %{
        providers: ["obsidian"],
        time_range: "all",
        obsidian_mode: "search",
        obsidian_sections: ["all"],
        search_terms: "project planning"
      }

      providers = Classifier.build_providers_from_classification(classification)

      obsidian = Enum.find(providers, &(&1["type"] == "obsidian"))
      assert obsidian["mode"] == "search"
      assert obsidian["query"] == "project planning"
    end

    test "builds todos mode" do
      classification = %{
        providers: ["obsidian"],
        time_range: "all",
        obsidian_mode: "todos",
        obsidian_sections: ["all"],
        search_terms: ""
      }

      providers = Classifier.build_providers_from_classification(classification)

      obsidian = Enum.find(providers, &(&1["type"] == "obsidian"))
      assert obsidian["mode"] == "todos"
    end

    test "builds signals provider" do
      classification = %{
        providers: ["signals"],
        time_range: "all",
        obsidian_mode: "auto",
        obsidian_sections: ["all"],
        search_terms: ""
      }

      providers = Classifier.build_providers_from_classification(classification)

      signals = Enum.find(providers, &(&1["type"] == "signals"))
      assert signals
    end

    test "builds email provider" do
      classification = %{
        providers: ["email"],
        time_range: "all",
        obsidian_mode: "auto",
        obsidian_sections: ["all"],
        search_terms: ""
      }

      providers = Classifier.build_providers_from_classification(classification)

      email = Enum.find(providers, &(&1["type"] == "email"))
      assert email["mode"] == "auto"
    end

    test "builds axiom_search provider" do
      classification = %{
        providers: ["axioms"],
        time_range: "all",
        obsidian_mode: "auto",
        obsidian_sections: ["all"],
        search_terms: ""
      }

      providers = Classifier.build_providers_from_classification(classification)

      axiom = Enum.find(providers, &(&1["type"] == "axiom_search"))
      assert axiom
    end
  end
end
