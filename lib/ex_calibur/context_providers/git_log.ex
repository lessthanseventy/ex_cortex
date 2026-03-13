defmodule ExCalibur.ContextProviders.GitLog do
  @moduledoc """
  Injects recent git commit history as prompt context.

  Config:
    "limit"  - number of commits (default: 20)
    "format" - "oneline" (default) or "full" (includes changed files via --stat)
    "label"  - section header (default: "## Recent Commits")

  Example:
    %{"type" => "git_log", "limit" => 20}
    %{"type" => "git_log", "limit" => 10, "format" => "full"}
  """

  @behaviour ExCalibur.ContextProviders.ContextProvider

  require Logger

  @impl true
  def build(config, _quest, _input) do
    limit = Map.get(config, "limit", 20)
    format = Map.get(config, "format", "oneline")
    label = Map.get(config, "label", "## Recent Commits")

    git_flags = if format == "full", do: ["--stat"], else: ["--oneline"]
    args = ["log"] ++ git_flags ++ ["-#{limit}"]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} ->
        trimmed = String.trim(output)

        if trimmed == "" do
          ""
        else
          "#{label}\n\n```\n#{trimmed}\n```"
        end

      {error, _} ->
        Logger.warning("[GitLogCtx] git log failed: #{String.slice(error, 0, 200)}")
        ""
    end
  end
end
