defmodule ExCortex.Tools.ObsidianToolsTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.CreateObsidianNote
  alias ExCortex.Tools.DailyNoteWrite
  alias ExCortex.Tools.ReadObsidian
  alias ExCortex.Tools.ReadObsidianFrontmatter
  alias ExCortex.Tools.SearchObsidian
  alias ExCortex.Tools.SearchObsidianContent

  test "SearchObsidian returns a valid ReqLLM.Tool struct" do
    tool = SearchObsidian.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "search_obsidian"
  end

  test "SearchObsidianContent returns a valid ReqLLM.Tool struct" do
    tool = SearchObsidianContent.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "search_obsidian_content"
  end

  test "ReadObsidian returns a valid ReqLLM.Tool struct" do
    tool = ReadObsidian.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "read_obsidian"
  end

  test "ReadObsidianFrontmatter returns a valid ReqLLM.Tool struct" do
    tool = ReadObsidianFrontmatter.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "read_obsidian_frontmatter"
  end

  test "CreateObsidianNote returns a valid ReqLLM.Tool struct" do
    tool = CreateObsidianNote.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "create_obsidian_note"
  end

  test "DailyNoteWrite returns a valid ReqLLM.Tool struct" do
    tool = DailyNoteWrite.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "daily_note_write"
  end

  test "Registry includes Obsidian read tools in all_safe" do
    tools = ExCortex.Tools.Registry.resolve_tools(:all_safe)
    names = Enum.map(tools, & &1.name)
    assert "search_obsidian" in names
    assert "search_obsidian_content" in names
    assert "read_obsidian" in names
    assert "read_obsidian_frontmatter" in names
    refute "create_obsidian_note" in names
    refute "daily_note_write" in names
  end

  test "Registry includes write tools in write tier" do
    tools = ExCortex.Tools.Registry.resolve_tools(:write)
    names = Enum.map(tools, & &1.name)
    assert "create_obsidian_note" in names
    assert "daily_note_write" in names
    # also has safe tools
    assert "search_obsidian" in names
  end
end
