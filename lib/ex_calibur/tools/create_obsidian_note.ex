defmodule ExCalibur.Tools.CreateObsidianNote do
  @moduledoc "Tool: create a new note in the Obsidian vault."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "create_obsidian_note",
      description: "Create a new note in the Obsidian vault with the given title and content.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "title" => %{"type" => "string", "description" => "Note title (filename without extension)"},
          "body" => %{"type" => "string", "description" => "Note content in Markdown"},
          "tags" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Optional tags to include in frontmatter"
          }
        },
        "required" => ["title", "body"]
      },
      callback: &call/1
    )
  end

  def call(%{"title" => title, "body" => body} = params) do
    tags = Map.get(params, "tags", [])
    vault = ExCalibur.Settings.get(:obsidian_vault)

    content = build_content(body, tags)
    args = vault_args(["create", title, "--content", content, "--overwrite"], vault)

    case System.cmd("obsidian-cli", args, stderr_to_stdout: true) do
      {_output, 0} -> {:ok, "Note '#{title}' created successfully"}
      {error, _} -> {:error, error}
    end
  end

  defp build_content(body, []), do: body

  defp build_content(body, tags) do
    tags_yaml = Enum.map_join(tags, "\n", &"  - #{&1}")
    "---\ntags:\n#{tags_yaml}\n---\n\n#{body}"
  end

  defp vault_args(args, nil), do: args
  defp vault_args(args, vault), do: args ++ ["--vault", vault]
end
