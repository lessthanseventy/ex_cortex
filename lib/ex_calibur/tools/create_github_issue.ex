defmodule ExCalibur.Tools.CreateGithubIssue do
  @moduledoc "Tool: create a GitHub issue via gh CLI."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "create_github_issue",
      description: "Create a new GitHub issue in the specified repository.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "title" => %{"type" => "string", "description" => "Issue title"},
          "body" => %{"type" => "string", "description" => "Issue body (markdown supported)"},
          "repo" => %{"type" => "string", "description" => "Repository in 'owner/repo' format (optional if default_repo configured)"},
          "labels" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Labels to apply to the issue"
          }
        },
        "required" => ["title", "body"]
      },
      callback: &call/1
    )
  end

  def call(%{"title" => title, "body" => body} = params) do
    repo = Map.get(params, "repo") || ExCalibur.Settings.get(:default_repo)

    case repo do
      nil ->
        {:error, "repo required — pass 'repo' param or configure default_repo in settings"}

      repo ->
        labels = Map.get(params, "labels", [])
        args = build_args(title, body, repo, labels)

        case System.cmd("gh", args, stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {error, _} -> {:error, error}
        end
    end
  end

  defp build_args(title, body, repo, []) do
    ["issue", "create", "--title", title, "--body", body, "--repo", repo]
  end

  defp build_args(title, body, repo, labels) do
    label_args = Enum.flat_map(labels, &["--label", &1])
    ["issue", "create", "--title", title, "--body", body, "--repo", repo] ++ label_args
  end
end
