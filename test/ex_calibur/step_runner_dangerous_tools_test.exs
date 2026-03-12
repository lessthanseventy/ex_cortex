defmodule ExCalibur.StepRunnerDangerousToolsTest do
  use ExUnit.Case, async: true

  alias ExCalibur.StepRunner

  test "new tools are marked dangerous" do
    assert StepRunner.dangerous?("merge_pr")
    assert StepRunner.dangerous?("git_pull")
    assert StepRunner.dangerous?("restart_app")
    assert StepRunner.dangerous?("close_issue")
  end

  test "safe tools are not marked dangerous" do
    refute StepRunner.dangerous?("read_file")
    refute StepRunner.dangerous?("list_files")
    refute StepRunner.dangerous?("run_sandbox")
  end
end
