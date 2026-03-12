defmodule ExCalibur.ClaudeClient do
  @moduledoc """
  Thin wrapper around ReqLLM for Anthropic Claude calls.

  Supports the three tiers used in quest escalation:
    - "claude_haiku"  → claude-haiku-4-5
    - "claude_sonnet" → claude-sonnet-4-6
    - "claude_opus"   → claude-opus-4-6

  Usage:
    ClaudeClient.complete("claude_sonnet", system_prompt, user_text)
    # => {:ok, "response text"}
    # => {:error, reason}
  """

  @model_ids %{
    "claude_haiku" => "anthropic:claude-haiku-4-5",
    "claude_sonnet" => "anthropic:claude-sonnet-4-6",
    "claude_opus" => "anthropic:claude-opus-4-6"
  }

  @doc """
  Call Claude synchronously.

  - `tier` — one of "claude_haiku", "claude_sonnet", "claude_opus"
  - `system_prompt` — the system prompt string
  - `user_text` — the user message string
  """
  def complete(tier, system_prompt, user_text) do
    model_spec = Map.fetch!(@model_ids, tier)

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_text}
    ]

    case ReqLLM.generate_text(model_spec, messages) do
      {:ok, response} -> {:ok, response.text}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  @doc "Returns true if an ANTHROPIC_API_KEY is configured."
  def configured? do
    key = ReqLLM.get_key(:anthropic_api_key) || System.get_env("ANTHROPIC_API_KEY")
    key != nil and key != ""
  end

  @doc "Returns the list of supported tier names."
  def tiers, do: Map.keys(@model_ids)

  @max_tool_iterations 5

  @doc """
  Run a multi-turn agent loop using ReqLLM's native tool calling.

  - `tier` — "claude_haiku" | "claude_sonnet" | "claude_opus"
  - `system_prompt` — system prompt string
  - `user_text` — initial user message
  - `tools` — list of %ReqLLM.Tool{} structs (from ExCalibur.Tools.Registry)

  Returns {:ok, text} on final answer or {:error, reason} on failure.
  """
  def complete_with_tools(tier, system_prompt, user_text, tools) do
    case Map.fetch(@model_ids, tier) do
      :error ->
        {:error, "unknown tier: #{tier}"}

      {:ok, model_spec} ->
        context =
          ReqLLM.Context.new([
            ReqLLM.Context.system(system_prompt),
            ReqLLM.Context.user(user_text)
          ])

        run_agent_loop(model_spec, context, tools, 0, [])
    end
  end

  # ---------------------------------------------------------------------------
  # Private — agent loop
  # ---------------------------------------------------------------------------

  defp run_agent_loop(_model_spec, _context, _tools, iter, tool_log) when iter >= @max_tool_iterations do
    {:error, :max_iterations_exceeded, tool_log}
  end

  defp run_agent_loop(model_spec, context, tools, iter, tool_log) do
    case ReqLLM.generate_text(model_spec, context, tools: tools) do
      {:ok, response} ->
        case ReqLLM.Response.classify(response) do
          %{type: :final_answer, text: text} ->
            {:ok, text, tool_log}

          %{type: :tool_calls, tool_calls: calls} ->
            {next_context, new_entries} = execute_tools_with_log(response.context, calls, tools)
            run_agent_loop(model_spec, next_context, tools, iter + 1, tool_log ++ new_entries)
        end

      {:error, reason} ->
        {:error, inspect(reason), tool_log}
    end
  rescue
    e -> {:error, Exception.message(e), tool_log}
  end

  defp execute_tools_with_log(context, calls, tools) do
    Enum.reduce(calls, {context, []}, fn call, {ctx, log} ->
      {name, id} = extract_call_info(call)
      args = extract_call_args(call)
      tool = Enum.find(tools, &(&1.name == name))

      result =
        if tool,
          do: ReqLLM.Tool.execute(tool, args),
          else: {:error, "Tool #{name} not found"}

      output =
        case result do
          {:ok, r} -> to_string(r)
          {:error, e} -> "Error: #{inspect(e)}"
        end

      result_content =
        case result do
          {:ok, r} -> to_string(r)
          {:error, e} -> Jason.encode!(%{error: to_string(e)})
        end

      msg = ReqLLM.Context.tool_result(id, name, result_content)
      next_ctx = ReqLLM.Context.append(ctx, msg)
      entry = %{tool: name, input: args, output: output}
      {next_ctx, log ++ [entry]}
    end)
  end

  defp extract_call_info(%ReqLLM.ToolCall{id: id, function: %{name: name}}), do: {name, id}
  defp extract_call_info(%{name: name, id: id}), do: {name, id}

  defp extract_call_args(%ReqLLM.ToolCall{function: %{arguments: args}}) when is_binary(args), do: Jason.decode!(args)

  defp extract_call_args(%ReqLLM.ToolCall{function: %{arguments: args}}), do: args
  defp extract_call_args(%{arguments: args}) when is_binary(args), do: Jason.decode!(args)
  defp extract_call_args(%{arguments: args}), do: args
  defp extract_call_args(_), do: %{}
end
