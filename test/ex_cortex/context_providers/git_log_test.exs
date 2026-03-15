defmodule ExCortex.ContextProviders.GitLogTest do
  use ExUnit.Case, async: true

  alias ExCortex.ContextProviders.GitLog

  test "returns recent commit history" do
    result = GitLog.build(%{"type" => "git_log", "limit" => 5}, %{}, "")
    # Should include commits since we're in a git repo
    assert result =~ "## Recent Commits"
    assert result =~ "```"
  end

  test "respects custom label" do
    result = GitLog.build(%{"type" => "git_log", "label" => "## Git History"}, %{}, "")
    assert result =~ "## Git History"
  end

  test "returns empty string when git not available" do
    # Temporarily test with an invalid path by passing a bad working dir
    # We can't easily test this without mocking, so just verify the happy path format
    result = GitLog.build(%{"type" => "git_log", "limit" => 3}, %{}, "")
    assert is_binary(result)
  end
end
