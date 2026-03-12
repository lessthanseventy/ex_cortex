defmodule ExCalibur.Tools.QueryJaeger do
  @moduledoc "Tool: query Jaeger for recent traces — useful for performance and error analysis."

  @default_url "http://localhost:16686"
  @service "ex_calibur"

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "query_jaeger",
      description: """
      Query Jaeger for recent OpenTelemetry traces from ex_calibur.
      Use this to find slow operations, failed LLM calls, expensive tool calls, or quest run timings.
      Returns a summary of recent traces sorted by duration (slowest first).
      """,
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "operation" => %{
            "type" => "string",
            "description" =>
              "Filter by operation name. Options: quest.run, quest.step, llm.complete, llm.complete_with_tools, llm.tool_call, or leave empty for all."
          },
          "lookback" => %{
            "type" => "string",
            "description" => "How far back to look. Examples: 1h, 4h, 24h. Defaults to 4h."
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Max traces to return (default 20, max 100)."
          },
          "min_duration_ms" => %{
            "type" => "integer",
            "description" => "Only return traces slower than this many milliseconds."
          }
        },
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(params) do
    base_url = Application.get_env(:ex_calibur, :jaeger_url, @default_url)
    operation = Map.get(params, "operation", "")
    lookback = Map.get(params, "lookback", "4h")
    limit = min(Map.get(params, "limit", 20), 100)
    min_duration_ms = Map.get(params, "min_duration_ms", 0)

    query =
      %{
        service: @service,
        limit: limit,
        lookback: lookback
      }
      |> then(fn q -> if operation == "", do: q, else: Map.put(q, :operation, operation) end)
      |> then(fn q ->
        if min_duration_ms > 0,
          do: Map.put(q, :minDuration, "#{min_duration_ms}ms"),
          else: q
      end)

    url = "#{base_url}/api/traces"

    case Req.get(url, params: query, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, format_traces(body, operation)}

      {:ok, %{status: 404}} ->
        {:error, "Jaeger not reachable at #{base_url} — is it running?"}

      {:ok, %{status: status}} ->
        {:error, "Jaeger returned HTTP #{status}"}

      {:error, reason} ->
        {:error, "Could not connect to Jaeger: #{inspect(reason)}"}
    end
  end

  defp format_traces(%{"data" => []}, op) do
    filter = if op == "", do: "", else: " for operation '#{op}'"
    "No traces found#{filter}. Either Jaeger is empty or the lookback window is too short."
  end

  defp format_traces(%{"data" => traces}, _op) when is_list(traces) do
    summaries =
      traces
      |> Enum.map(&summarize_trace/1)
      |> Enum.sort_by(& &1.duration_ms, :desc)

    total = length(summaries)
    errors = Enum.count(summaries, & &1.has_error)
    avg_ms = if total > 0, do: Enum.sum(Enum.map(summaries, & &1.duration_ms)) / total, else: 0
    slowest = List.first(summaries)

    header = """
    ## Jaeger Trace Summary (#{total} trace#{if total != 1, do: "s"})
    Errors: #{errors} | Avg duration: #{round(avg_ms)}ms | Slowest: #{slowest && slowest.duration_ms}ms

    """

    rows =
      summaries
      |> Enum.take(20)
      |> Enum.map_join("\n", fn t ->
        error_flag = if t.has_error, do: " ❌", else: ""
        attrs = if t.attrs == "", do: "", else: " [#{t.attrs}]"
        "- #{t.root_op}#{error_flag} #{t.duration_ms}ms#{attrs}"
      end)

    header <> rows
  end

  defp format_traces(_, _), do: "Unexpected response format from Jaeger."

  defp summarize_trace(%{"spans" => spans}) when is_list(spans) do
    root = Enum.min_by(spans, fn s -> s["startTime"] || 0 end, fn -> %{} end)
    root_op = root["operationName"] || "unknown"

    total_duration_us =
      spans
      |> Enum.map(&(&1["duration"] || 0))
      |> Enum.max(fn -> 0 end)

    has_error =
      Enum.any?(spans, fn span ->
        tags = span["tags"] || []

        Enum.any?(tags, fn t -> t["key"] == "error" and t["value"] == true end) or
          Enum.any?(tags, fn t -> t["key"] == "otel.status_code" and t["value"] == "ERROR" end)
      end)

    key_attrs =
      (root["tags"] || [])
      |> Enum.filter(fn t -> t["key"] in ~w(quest.name llm.model step.name tool.name) end)
      |> Enum.map_join(", ", fn t -> "#{t["key"]}=#{t["value"]}" end)

    %{
      root_op: root_op,
      duration_ms: div(total_duration_us, 1000),
      has_error: has_error,
      span_count: length(spans),
      attrs: key_attrs
    }
  end

  defp summarize_trace(_), do: %{root_op: "unknown", duration_ms: 0, has_error: false, span_count: 0, attrs: ""}
end
