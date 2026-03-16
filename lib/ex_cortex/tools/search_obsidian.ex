defmodule ExCortex.Tools.SearchObsidian do
  @moduledoc "Tool: fuzzy search Obsidian vault note titles."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "search_obsidian",
      description:
        "Search Obsidian vault by note title (fuzzy substring match). Returns matching note names. For searching inside note bodies, use search_obsidian_content instead. Example: search_obsidian(query: \"meeting notes\")",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "Search query to match against note titles"}
        },
        "required" => ["query"]
      },
      callback: &call/1
    )
  end

  def call(%{"query" => query}) do
    vault = ExCortex.Settings.get(:obsidian_vault)
    args = vault_args(["list"], vault)

    case System.cmd("obsidian-cli", args, stderr_to_stdout: true) do
      {output, 0} ->
        results =
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(&String.contains?(String.downcase(&1), String.downcase(query)))

        {:ok, Enum.join(results, "\n")}

      {error, _} ->
        {:error, error}
    end
  end

  defp vault_args(args, nil), do: args
  defp vault_args(args, vault), do: args ++ ["--vault", vault]
end
