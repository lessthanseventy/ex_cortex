defmodule ExCortex.LLM.ToolExecutor do
  @moduledoc """
  Shared tool execution logic extracted from Claude and Ollama LLM providers.

  Handles circuit breaker, dangerous tool interception, middleware wrapping,
  and consistent output formatting for tool calls.
  """

  alias ExCortex.Ruminations.ImpulseRunner
  alias ExCortex.Ruminations.Middleware

  require Logger

  @empty_threshold 3

  @doc "Execute a single tool call with middleware, circuit breaker, and dangerous tool handling."
  def execute(tool_name, tool_args, tools, breaker_state, opts \\ []) do
    prior_count = Map.get(breaker_state, tool_name, 0)

    if prior_count >= @empty_threshold do
      execute_tripped(tool_name, tool_args, breaker_state)
    else
      execute_active(tool_name, tool_args, tools, breaker_state, opts)
    end
  end

  @doc "Returns true if the output is considered empty for circuit breaker purposes."
  def empty_result?(output) when is_binary(output) do
    trimmed = String.trim(output)

    trimmed == "" or
      trimmed == "[]" or
      trimmed == "[]\n" or
      String.contains?(trimmed, "is not available in this step")
  end

  def empty_result?(_), do: true

  # Circuit breaker tripped — skip tool entirely
  defp execute_tripped(tool_name, tool_args, breaker_state) do
    out =
      "Tool #{tool_name} returned empty results #{Map.get(breaker_state, tool_name, 0)} times. Skipping — proceed with available information."

    Logger.debug("[ToolExecutor] circuit breaker: skipping #{tool_name}")
    {out, %{tool: tool_name, input: tool_args, output: out}, breaker_state}
  end

  # Active execution path — check dangerous, then run
  defp execute_active(tool_name, tool_args, tools, breaker_state, opts) do
    dangerous_mode = Keyword.get(opts, :dangerous_tool_mode, "execute")
    rumination_id = Keyword.get(opts, :rumination_id)
    middleware = Keyword.get(opts, :middleware, [])

    if ImpulseRunner.dangerous?(tool_name) and dangerous_mode != "execute" do
      execute_dangerous(tool_name, tool_args, breaker_state, dangerous_mode, rumination_id)
    else
      execute_safe(tool_name, tool_args, tools, breaker_state, middleware)
    end
  end

  defp execute_dangerous(tool_name, tool_args, breaker_state, "dry_run", _rumination_id) do
    out = "DRY RUN: Would have called #{tool_name} with #{Jason.encode!(tool_args)}. No action taken."
    Logger.info("[ToolExecutor] dry_run: #{tool_name}")
    {out, %{tool: tool_name, input: tool_args, output: out}, breaker_state}
  end

  defp execute_dangerous(tool_name, tool_args, breaker_state, "intercept", rumination_id) do
    ImpulseRunner.intercept_dangerous_tool(tool_name, tool_args, rumination_id)
    out = "Tool call queued for human approval. Proposal ID: #{rumination_id}. Continue without this result."
    Logger.info("[ToolExecutor] intercepted: #{tool_name}")
    {out, %{tool: tool_name, input: tool_args, output: out}, breaker_state}
  end

  defp execute_safe(tool_name, tool_args, tools, breaker_state, middleware) do
    tool = Enum.find(tools, &(&1.name == tool_name))

    result =
      if middleware == [] do
        run_tool(tool, tool_name, tool_args)
      else
        Middleware.wrap_tool(middleware, tool_name, tool_args, fn ->
          run_tool(tool, tool_name, tool_args)
        end)
      end

    out =
      case result do
        {:ok, v} -> to_string(v)
        {:error, e} -> "Error: #{inspect(e)}"
      end

    updated_bs = update_breaker(tool_name, out, breaker_state)

    {out, %{tool: tool_name, input: tool_args, output: out}, updated_bs}
  end

  defp run_tool(nil, tool_name, _tool_args) do
    {:error, "Tool #{tool_name} not found"}
  end

  defp run_tool(tool, _tool_name, tool_args) do
    # Support both ReqLLM.Tool structs (callback field) and test stubs with a :function field
    if Map.has_key?(tool, :function) and is_function(tool.function) do
      tool.function.(tool_args)
    else
      ReqLLM.Tool.execute(tool, tool_args)
    end
  end

  defp update_breaker(tool_name, output, breaker_state) do
    if empty_result?(output) do
      count = Map.get(breaker_state, tool_name, 0) + 1
      Map.put(breaker_state, tool_name, count)
    else
      Map.put(breaker_state, tool_name, 0)
    end
  end
end
