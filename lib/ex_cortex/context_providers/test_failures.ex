defmodule ExCortex.ContextProviders.TestFailures do
  @moduledoc """
  Runs mix test and injects only the failure output — not the passing dots.

  Returns empty string when all tests pass (unless show_pass: true).
  Strips the passing output and formats only the numbered failure blocks.

  Config:
    "show_pass" - if true, returns "All N tests passing." on success (default: false)
    "label"     - section header (default: "## Test Failures")

  Example:
    %{"type" => "test_failures"}
    %{"type" => "test_failures", "show_pass" => true}
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  require Logger

  @impl true
  def build(config, _thought, _input) do
    label = Map.get(config, "label", "## Test Failures")
    show_pass = Map.get(config, "show_pass", false)
    working_dir = File.cwd!()

    case ExCortex.Sandbox.run(%{cmd: "mix test", mode: :host}, working_dir) do
      {:ok, output, 0} ->
        if show_pass do
          count = count_tests(output)
          "#{label}\n\nAll #{count} tests passing."
        else
          ""
        end

      {:ok, output, _exit_code} ->
        failures = extract_failures(output)

        if failures == "" do
          ""
        else
          "#{label}\n\n#{failures}"
        end

      {:error, reason} ->
        Logger.warning("[TestFailuresCtx] mix test failed: #{inspect(reason)}")
        ""
    end
  end

  # Extract everything from the first numbered failure to just before "Finished in"
  defp extract_failures(output) do
    lines = String.split(output, "\n")

    failure_start = Enum.find_index(lines, &Regex.match?(~r/^\s+1\) /, &1))

    if failure_start do
      lines
      |> Enum.drop(failure_start)
      |> Enum.take_while(&(not String.starts_with?(&1, "Finished in")))
      |> Enum.join("\n")
      |> String.trim()
    else
      ""
    end
  end

  defp count_tests(output) do
    case Regex.run(~r/(\d+) tests?, 0 failures/, output) do
      [_, count] -> count
      _ -> "?"
    end
  end
end
