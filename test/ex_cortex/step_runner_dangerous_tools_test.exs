defmodule ExCortex.Thoughts.ImpulseRunnerDangerousToolsTest do
  use ExUnit.Case, async: true

  alias ExCortex.Thoughts.ImpulseRunner

  test "new tools are marked dangerous" do
    assert ImpulseRunner.dangerous?("merge_pr")
    assert ImpulseRunner.dangerous?("git_pull")
    assert ImpulseRunner.dangerous?("restart_app")
    assert ImpulseRunner.dangerous?("close_issue")
  end

  test "safe tools are not marked dangerous" do
    refute ImpulseRunner.dangerous?("read_file")
    refute ImpulseRunner.dangerous?("list_files")
    refute ImpulseRunner.dangerous?("run_sandbox")
  end
end
