defmodule ExCortex.Thoughts.ImpulseRunnerDangerousTest do
  use ExCortex.DataCase

  alias ExCortex.Thoughts.ImpulseRunner

  describe "dangerous?/1" do
    test "returns true for dangerous tools" do
      assert ImpulseRunner.dangerous?("send_email")
      assert ImpulseRunner.dangerous?("create_github_issue")
      assert ImpulseRunner.dangerous?("comment_github")
      assert ImpulseRunner.dangerous?("run_thought")
    end

    test "returns false for safe tools" do
      refute ImpulseRunner.dangerous?("web_search")
      refute ImpulseRunner.dangerous?("query_memory")
      refute ImpulseRunner.dangerous?("search_obsidian")
    end
  end
end
