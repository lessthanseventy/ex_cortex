defmodule ExCortex.ContextProviders.PrDiff do
  @moduledoc """
  Fetches a GitHub PR diff and injects it as prompt context.

  Requires the "pr" config key with the PR number. Uses the gh CLI.

  Config:
    "pr"    - PR number (required)
    "label" - section header (default: "## PR Diff")

  Example:
    %{"type" => "pr_diff", "pr" => 42}
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  require Logger

  @max_bytes 8_000

  @impl true
  def build(config, _thought, _input) do
    case Map.get(config, "pr") do
      nil ->
        Logger.warning("[PrDiffCtx] No 'pr' number in config")
        ""

      pr ->
        fetch_diff(to_string(pr), config)
    end
  end

  defp fetch_diff(pr, config) do
    label = Map.get(config, "label", "## PR Diff")
    repo = ExCortex.Settings.get(:default_repo)

    args = ["pr", "diff", pr] ++ if(repo, do: ["--repo", repo], else: [])

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} ->
        truncated = String.slice(output, 0, @max_bytes)
        suffix = if byte_size(output) > @max_bytes, do: "\n... (truncated)", else: ""
        "#{label}\n\n```diff\n#{String.trim(truncated)}#{suffix}\n```"

      {error, _} ->
        Logger.warning("[PrDiffCtx] gh pr diff #{pr} failed: #{String.slice(error, 0, 200)}")
        ""
    end
  end
end
