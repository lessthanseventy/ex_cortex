defmodule ExCortex.Tools.RunSandbox do
  @moduledoc "Tool: run an allowlisted mix command in the working directory."

  @allowed_prefixes [
    "mix test",
    "mix credo",
    "mix dialyzer",
    "mix excessibility",
    "mix format",
    "mix deps.audit"
  ]

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "run_sandbox",
      description:
        "Run an allowlisted mix command in the working directory. Allowed: mix test, mix credo, mix dialyzer, mix excessibility, mix format, mix deps.audit.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "command" => %{
            "type" => "string",
            "description" => "Command to run (must start with an allowlisted prefix)"
          }
        },
        "required" => ["command"]
      },
      callback: &call/1
    )
  end

  def call(%{"command" => command} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())

    if Enum.any?(@allowed_prefixes, &String.starts_with?(command, &1)) do
      case ExCortex.Sandbox.run(%{cmd: command, mode: :host}, working_dir) do
        {:ok, output, exit_code} -> {:ok, "Exit #{exit_code}:\n#{output}"}
        {:error, reason} -> {:error, "Sandbox error: #{inspect(reason)}"}
      end
    else
      {:error, "Command not allowed. Must start with: #{Enum.join(@allowed_prefixes, ", ")}"}
    end
  end
end
