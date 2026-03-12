defmodule ExCalibur.Tools.GitCommitTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Tools.GitCommit

  test "req_llm_tool returns valid tool struct" do
    tool = GitCommit.req_llm_tool()
    assert tool.name == "git_commit"
    assert "files" in tool.parameter_schema["required"]
    assert "message" in tool.parameter_schema["required"]
  end
end
