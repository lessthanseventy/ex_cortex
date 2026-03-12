defmodule ExCalibur.StepRunnerDangerousTest do
  use ExCalibur.DataCase

  alias ExCalibur.StepRunner

  describe "dangerous?/1" do
    test "returns true for dangerous tools" do
      assert StepRunner.dangerous?("send_email")
      assert StepRunner.dangerous?("create_github_issue")
      assert StepRunner.dangerous?("comment_github")
      assert StepRunner.dangerous?("run_quest")
    end

    test "returns false for safe tools" do
      refute StepRunner.dangerous?("web_search")
      refute StepRunner.dangerous?("query_lore")
      refute StepRunner.dangerous?("search_obsidian")
    end
  end
end
