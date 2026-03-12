defmodule ExCalibur.Tools.ReadObsidian do
  @moduledoc "Tool: read the full contents of an Obsidian note by title."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_obsidian",
      description: "Read the full contents of an Obsidian note by title.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "title" => %{"type" => "string", "description" => "Note title to read"}
        },
        "required" => ["title"]
      },
      callback: &call/1
    )
  end

  def call(%{"title" => title}) do
    vault = ExCalibur.Settings.get(:obsidian_vault)
    args = vault_args(["print", title], vault)

    case System.cmd("obsidian-cli", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  defp vault_args(args, nil), do: args
  defp vault_args(args, vault), do: args ++ ["--vault", vault]
end
