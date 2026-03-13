defmodule ExCalibur.ContextProviders.Sandbox do
  @moduledoc """
  Runs allowlisted mix commands before the step and injects their output as context.

  The model receives the results directly — no tool call needed for data retrieval.

  Config:
    "commands" - list of mix commands to run (must be in the allowlist)
    "label"    - optional section header (default: "## Codebase Analysis")

  Example:
    %{"type" => "sandbox", "commands" => ["mix credo --all", "mix test"]}
  """

  @behaviour ExCalibur.ContextProviders.ContextProvider

  require Logger

  @allowed_prefixes [
    "mix test",
    "mix credo",
    "mix dialyzer",
    "mix excessibility",
    "mix format",
    "mix deps.audit"
  ]

  @impl true
  def build(config, _quest, _input) do
    commands = Map.get(config, "commands", [])
    label = Map.get(config, "label", "## Codebase Analysis")
    working_dir = File.cwd!()

    results =
      commands
      |> Enum.map(fn cmd ->
        if Enum.any?(@allowed_prefixes, &String.starts_with?(cmd, &1)) do
          run_command(cmd, working_dir)
        else
          Logger.warning("[SandboxCtx] Skipping disallowed command: #{cmd}")
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if results == [] do
      ""
    else
      body = Enum.join(results, "\n\n")

      String.trim("""
      #{label}

      #{body}
      """)
    end
  end

  defp run_command(cmd, working_dir) do
    Logger.debug("[SandboxCtx] Running: #{cmd}")

    case ExCalibur.Sandbox.run(%{cmd: cmd, mode: :host}, working_dir) do
      {:ok, output, exit_code} ->
        status = if exit_code == 0, do: "✓", else: "✗ (exit #{exit_code})"
        "### #{cmd} #{status}\n#{String.trim(output)}"

      {:error, reason} ->
        Logger.warning("[SandboxCtx] #{cmd} failed: #{inspect(reason)}")
        "### #{cmd} — failed: #{inspect(reason)}"
    end
  end
end
