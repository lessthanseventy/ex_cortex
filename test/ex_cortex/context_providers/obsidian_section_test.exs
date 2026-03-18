defmodule ExCortex.ContextProviders.ObsidianSectionTest do
  use ExUnit.Case, async: true

  alias ExCortex.ContextProviders.Obsidian

  @sample_content """
  > [!abstract] brain dump
  > you don't have to organize it. just capture it.
  > thought about making muse smarter
  > another captured idea

  > [!todo] todo
  > - [ ] fix the tests
  > - [x] update CLAUDE.md

  > [!tip] stuff that came up
  > remember to check X
  > also look at Y
  """

  describe "extract_sections/2" do
    test "returns full content unchanged for [\"all\"]" do
      assert Obsidian.extract_sections(@sample_content, ["all"]) == @sample_content
    end

    test "extracts a single section" do
      result = Obsidian.extract_sections(@sample_content, ["brain_dump"])

      assert result =~ "you don't have to organize it. just capture it."
      assert result =~ "thought about making muse smarter"
      assert result =~ "another captured idea"
      refute result =~ "fix the tests"
      refute result =~ "remember to check X"
    end

    test "extracts multiple sections" do
      result = Obsidian.extract_sections(@sample_content, ["brain_dump", "todo"])

      assert result =~ "thought about making muse smarter"
      assert result =~ "fix the tests"
      refute result =~ "remember to check X"
    end

    test "returns empty string when section not found" do
      assert Obsidian.extract_sections(@sample_content, ["nonexistent"]) == ""
    end

    test "case-insensitive matching" do
      content = """
      > [!abstract] Brain Dump
      > some thoughts here
      """

      result = Obsidian.extract_sections(content, ["brain_dump"])
      assert result =~ "some thoughts here"
    end

    test "handles underscores to spaces in section names" do
      content = """
      > [!tip] stuff that came up
      > important thing
      """

      result = Obsidian.extract_sections(content, ["stuff_that_came_up"])
      assert result =~ "important thing"
    end

    test "strips > prefix from collected lines" do
      result = Obsidian.extract_sections(@sample_content, ["todo"])

      refute result =~ ~r/^>/m
      assert result =~ "- [ ] fix the tests"
    end

    test "sections are joined with double newlines" do
      result = Obsidian.extract_sections(@sample_content, ["brain_dump", "todo"])

      assert result =~ "\n\n"
    end

    test "handles content with no callout blocks" do
      plain = "just some regular text\nno callouts here"

      assert Obsidian.extract_sections(plain, ["brain_dump"]) == ""
      assert Obsidian.extract_sections(plain, ["all"]) == plain
    end

    test "handles empty content" do
      assert Obsidian.extract_sections("", ["brain_dump"]) == ""
      assert Obsidian.extract_sections("", ["all"]) == ""
    end
  end
end
