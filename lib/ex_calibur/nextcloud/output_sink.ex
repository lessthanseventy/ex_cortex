defmodule ExCalibur.Nextcloud.OutputSink do
  @moduledoc "Writes quest results to Nextcloud as markdown files."

  alias ExCalibur.Nextcloud.Client

  require Logger

  @base_path "/ExCalibur"

  def write_result(quest_name, result, opts \\ []) do
    if Client.configured?() do
      do_write(quest_name, result, opts)
    else
      Logger.debug("[NextcloudSink] Nextcloud not configured, skipping write")
      :skip
    end
  end

  defp do_write(quest_name, result, opts) do
    folder = Keyword.get(opts, :folder, @base_path)
    date = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")
    slug = quest_name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
    filename = "#{date}-#{slug}.md"
    path = "#{folder}/#{filename}"

    content = format_result(quest_name, result, date)

    # Ensure folder exists
    Client.mkcol(folder)

    case Client.put_file(path, content) do
      :ok ->
        Logger.info("[NextcloudSink] Wrote #{path}")
        {:ok, path}

      {:error, reason} ->
        Logger.warning("[NextcloudSink] Failed to write #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp format_result(quest_name, result, date) when is_map(result) do
    verdict = Map.get(result, :verdict, "n/a")
    output = Map.get(result, :output, "")
    steps = Map.get(result, :steps, [])
    tool_calls = Map.get(result, :tool_calls, [])

    step_summary =
      if steps == [] do
        "_No step details._"
      else
        Enum.map_join(steps, "\n", fn step ->
          v = Map.get(step, :verdict, "n/a")
          who = Map.get(step, :who, "unknown")
          "- **#{who}**: #{v}"
        end)
      end

    tool_summary =
      if tool_calls == [] do
        ""
      else
        Enum.map_join(tool_calls, "\n", fn tc ->
          name = Map.get(tc, :tool, "unknown")
          "- `#{name}`"
        end)
      end

    String.trim("""
    # #{quest_name}

    **Date:** #{date}
    **Verdict:** #{verdict}

    ## Output

    #{output}

    ## Steps

    #{step_summary}
    #{if tool_summary == "", do: "", else: "\n## Tool Calls\n\n#{tool_summary}"}
    """)
  end

  defp format_result(quest_name, result, date) when is_binary(result) do
    String.trim("""
    # #{quest_name}

    **Date:** #{date}

    #{result}
    """)
  end

  defp format_result(quest_name, result, date) do
    format_result(quest_name, inspect(result), date)
  end
end