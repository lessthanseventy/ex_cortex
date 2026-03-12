defmodule ExCalibur.Tools.GithubToolsTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Tools.CommentGithub
  alias ExCalibur.Tools.CreateGithubIssue
  alias ExCalibur.Tools.ListGithubNotifications
  alias ExCalibur.Tools.ReadGithubIssue
  alias ExCalibur.Tools.SearchGithub

  test "SearchGithub returns a valid ReqLLM.Tool struct" do
    tool = SearchGithub.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "search_github"
  end

  test "ReadGithubIssue returns a valid ReqLLM.Tool struct" do
    tool = ReadGithubIssue.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "read_github_issue"
  end

  test "ListGithubNotifications returns a valid ReqLLM.Tool struct" do
    tool = ListGithubNotifications.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "list_github_notifications"
  end

  test "CreateGithubIssue returns a valid ReqLLM.Tool struct" do
    tool = CreateGithubIssue.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "create_github_issue"
  end

  test "CommentGithub returns a valid ReqLLM.Tool struct" do
    tool = CommentGithub.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "comment_github"
  end

  test "safe GitHub tools appear in all_safe tier" do
    tools = ExCalibur.Tools.Registry.resolve_tools(:all_safe)
    names = Enum.map(tools, & &1.name)
    assert "search_github" in names
    assert "read_github_issue" in names
    assert "list_github_notifications" in names
    refute "create_github_issue" in names
    refute "comment_github" in names
  end

  test "dangerous GitHub tools appear in dangerous tier but not safe" do
    safe_names = :all_safe |> ExCalibur.Tools.Registry.resolve_tools() |> Enum.map(& &1.name)
    dangerous_names = :dangerous |> ExCalibur.Tools.Registry.resolve_tools() |> Enum.map(& &1.name)

    assert "create_github_issue" in dangerous_names
    assert "comment_github" in dangerous_names
    refute "create_github_issue" in safe_names
    refute "comment_github" in safe_names
  end

  test "ReadGithubIssue tool struct has correct required fields" do
    tool = ReadGithubIssue.req_llm_tool()
    required = tool.parameter_schema["required"]
    assert "number" in required
    refute "repo" in required
  end
end
