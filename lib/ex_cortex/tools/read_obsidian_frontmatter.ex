defmodule ExCortex.Tools.ReadObsidianFrontmatter do
  @moduledoc "Tool: read the YAML frontmatter of an Obsidian note."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_obsidian_frontmatter",
      description: "Read the YAML frontmatter of an Obsidian note by title. Returns only the frontmatter section.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "title" => %{"type" => "string", "description" => "Note title to read frontmatter from"}
        },
        "required" => ["title"]
      },
      callback: &call/1
    )
  end

  def call(%{"title" => title}) do
    vault = ExCortex.Settings.get(:obsidian_vault)
    args = vault_args(["frontmatter", title, "--print"], vault)

    case System.cmd("obsidian-cli", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  defp vault_args(args, nil), do: args
  defp vault_args(args, vault), do: args ++ ["--vault", vault]
end
