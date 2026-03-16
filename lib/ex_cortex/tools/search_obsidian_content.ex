defmodule ExCortex.Tools.SearchObsidianContent do
  @moduledoc "Tool: search Obsidian vault note content."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "search_obsidian_content",
      description:
        "Search inside Obsidian note bodies for a term. Returns matching note names with excerpts. For title-only search (faster), use search_obsidian instead. Example: search_obsidian_content(query: \"project deadline\")",
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
    vault = ExCortex.Settings.get(:obsidian_vault)
    args = vault_args(["search-content", query, "--no-interactive", "--format", "text"], vault)

    case System.cmd("obsidian-cli", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  defp vault_args(args, nil), do: args
  defp vault_args(args, vault), do: args ++ ["--vault", vault]
end
