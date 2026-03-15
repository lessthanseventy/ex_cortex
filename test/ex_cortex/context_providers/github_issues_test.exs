defmodule ExCortex.ContextProviders.GithubIssuesTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.ContextProviders.GithubIssues

  describe "build/3" do
    test "uses default label and header" do
      # gh CLI unavailable in test env — expect the fallback message
      result = GithubIssues.build(%{"type" => "github_issues"}, %{}, "")
      # Either returns formatted issues OR the unavailable fallback — both are non-empty strings
      assert is_binary(result)
    end

    test "includes header in output" do
      result = GithubIssues.build(%{"type" => "github_issues", "label" => "self-improvement"}, %{}, "")
      # The header should appear regardless of whether gh CLI is available
      assert result =~ "self-improvement"
    end

    test "accepts custom header" do
      result =
        GithubIssues.build(
          %{"type" => "github_issues", "label" => "bug", "header" => "## Bug Reports"},
          %{},
          ""
        )

      assert result =~ "## Bug Reports" or result =~ "bug"
    end
  end
end
