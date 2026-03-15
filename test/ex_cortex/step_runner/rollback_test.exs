defmodule ExCortex.Thoughts.ImpulseRunner.RollbackTest do
  use ExUnit.Case, async: true

  alias ExCortex.Thoughts.ImpulseRunner

  describe "has_write_tools?/1" do
    test "detects write_file" do
      assert ImpulseRunner.has_write_tools?(["run_sandbox", "write_file", "read_file"])
    end

    test "detects edit_file" do
      assert ImpulseRunner.has_write_tools?(["edit_file"])
    end

    test "detects git_commit" do
      assert ImpulseRunner.has_write_tools?(["git_commit"])
    end

    test "detects create_obsidian_note" do
      assert ImpulseRunner.has_write_tools?(["create_obsidian_note"])
    end

    test "detects daily_obsidian" do
      assert ImpulseRunner.has_write_tools?(["daily_obsidian"])
    end

    test "returns false for read-only tools" do
      refute ImpulseRunner.has_write_tools?(["run_sandbox", "read_file", "query_lore"])
    end

    test "returns false for empty list" do
      refute ImpulseRunner.has_write_tools?([])
    end

    test "returns false for nil" do
      refute ImpulseRunner.has_write_tools?(nil)
    end
  end
end
