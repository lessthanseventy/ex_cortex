defmodule ExCalibur.Tools.SearchObsidianContent do
  @moduledoc "Tool: search Obsidian vault note content."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "search_obsidian_content",
      description: "Search Obsidian vault note contents for a search term. Returns matching note names and excerpts.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "Search term to find in note contents"}
        },
        "required" => ["query"]
      },
      callback: &call/1
    )
  end

  def call(%{"query" => query}) do
    vault = ExCalibur.Settings.get(:obsidian_vault)
    args = vault_args(["search-content", query, "--no-interactive", "--format", "text"], vault)

    case System.cmd("obsidian-cli", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  defp vault_args(args, nil), do: args
  defp vault_args(args, vault), do: args ++ ["--vault", vault]
end
