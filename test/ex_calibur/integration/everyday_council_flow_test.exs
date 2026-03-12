defmodule ExCalibur.Integration.EverydayCouncilFlowTest do
  use ExCalibur.DataCase, async: false

  alias ExCalibur.Charters.EverydayCouncil
  alias ExCalibur.Sources.Book

  test "resource_definitions returns valid member configs" do
    defs = EverydayCouncil.resource_definitions()
    assert defs != []

    Enum.each(defs, fn d ->
      assert d.type == "role"
      assert is_binary(d.config["member_id"])
      assert d.config["tools"] in ["all_safe", "write", "dangerous"]
    end)
  end

  test "journal-keeper gets write tool tier" do
    defs = EverydayCouncil.resource_definitions()
    journal_keepers = Enum.filter(defs, &(&1.config["member_id"] == "journal-keeper"))
    assert journal_keepers != []

    Enum.each(journal_keepers, fn d ->
      assert d.config["tools"] == "write"
    end)
  end

  test "quest_definitions includes source-triggered Smart Intake" do
    quests = EverydayCouncil.quest_definitions()
    intake = Enum.find(quests, &(&1.name == "Smart Intake"))
    assert intake
    assert intake.trigger == "source"
    assert "query_lore" in intake.loop_tools
    assert "search_obsidian" in intake.loop_tools
  end

  test "quest_definitions includes scheduled Morning Briefing" do
    quests = EverydayCouncil.quest_definitions()
    briefing = Enum.find(quests, &(&1.name == "Morning Briefing"))
    assert briefing
    assert briefing.trigger == "scheduled"
    assert briefing.output_type == "artifact"
  end

  test "campaign_definitions includes Intake Loop" do
    campaigns = EverydayCouncil.campaign_definitions()
    intake_loop = Enum.find(campaigns, &(&1.name == "Intake Loop"))
    assert intake_loop
    assert intake_loop.trigger == "source"
  end

  test "Books includes Everyday Council entries" do
    books = Book.for_guild("Everyday Council")
    assert books != []
  end

  test "Registry resolve_tools(:write) includes obsidian write tools" do
    tools = ExCalibur.Tools.Registry.resolve_tools(:write)
    names = Enum.map(tools, & &1.name)
    assert "create_obsidian_note" in names
    assert "daily_obsidian" in names
    assert "query_lore" in names
  end

  test "Registry resolve_tools(:all_safe) includes search tools" do
    tools = ExCalibur.Tools.Registry.resolve_tools(:all_safe)
    names = Enum.map(tools, & &1.name)
    assert "search_obsidian" in names
    assert "web_search" in names
    assert "search_email" in names
    assert "search_github" in names
  end
end
