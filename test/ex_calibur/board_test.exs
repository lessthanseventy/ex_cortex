defmodule ExCalibur.BoardTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Board

  describe "all/0" do
    test "returns at least 16 templates" do
      assert length(Board.all()) >= 16
    end

    test "all templates have required fields" do
      for t <- Board.all() do
        assert is_binary(t.id), "#{t.id} missing id"
        assert is_binary(t.name), "#{t.id} missing name"

        assert t.category in [:triage, :reporting, :generation, :review, :onboarding],
               "#{t.id} has invalid category #{t.category}"

        assert is_list(t.quest_definitions), "#{t.id} missing quest_definitions"
        assert length(t.quest_definitions) > 0, "#{t.id} has no quest_definitions"
        assert is_map(t.campaign_definition), "#{t.id} missing campaign_definition"
      end
    end

    test "all template ids are unique" do
      ids = Enum.map(Board.all(), & &1.id)
      assert length(ids) == length(Enum.uniq(ids))
    end
  end

  describe "by_category/1" do
    test "returns only templates for that category" do
      triage = Board.by_category(:triage)
      assert length(triage) > 0
      assert Enum.all?(triage, &(&1.category == :triage))
    end
  end

  describe "get/1" do
    test "finds template by id" do
      template = Board.get("jira_ticket_triage")
      assert template.name == "Jira Ticket Triage"
    end

    test "returns nil for unknown id" do
      assert Board.get("nonexistent") == nil
    end
  end

  describe "check_requirements/1" do
    test "returns list of {met, label} tuples" do
      template = Board.get("incident_postmortem")
      # no requirements
      assert Board.check_requirements(template) == []
    end

    test "returns false for missing source type" do
      template = Board.get("jira_ticket_triage")
      results = Board.check_requirements(template)
      # jira_ticket_triage requires {:source_type, "webhook"} — no webhook sources in test DB
      {webhook_met, webhook_label} = List.first(results)
      refute webhook_met
      assert webhook_label =~ "source"
    end
  end

  describe "readiness/1" do
    test "returns :ready for template with no requirements" do
      template = Board.get("incident_postmortem")
      assert Board.readiness(template) == :ready
    end

    test "returns :unavailable or :almost when requirements missing" do
      template = Board.get("jira_ticket_triage")
      # requires webhook source + slack herald — webhook source won't be configured
      assert Board.readiness(template) in [:unavailable, :almost]
    end
  end
end
