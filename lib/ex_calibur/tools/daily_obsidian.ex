defmodule ExCalibur.Tools.DailyObsidian do
  @moduledoc "Tool: append content to today's daily note in Obsidian."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "daily_obsidian",
      description: "Append content to today's daily note in Obsidian. Creates the note if it does not exist.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "content" => %{"type" => "string", "description" => "Content to append to today's daily note"}
        },
        "required" => ["content"]
      },
      callback: &call/1
    )
  end

  def call(%{"content" => content}) do
    vault = ExCalibur.Settings.get(:obsidian_vault)
    today = Date.to_iso8601(Date.utc_today())
    args = vault_args(["create", today, "--content", content, "--append"], vault)

    case System.cmd("obsidian-cli", args, stderr_to_stdout: true) do
      {_output, 0} -> {:ok, "Appended to daily note #{today}"}
      {error, _} -> {:error, error}
    end
  end

  defp vault_args(args, nil), do: args
  defp vault_args(args, vault), do: args ++ ["--vault", vault]
end
