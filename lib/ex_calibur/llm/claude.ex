defmodule ExCalibur.LLM.Claude do
  @moduledoc "Claude (Anthropic) LLM provider."
  @behaviour ExCalibur.LLM

  require Logger

  @model_ids %{
    "claude_haiku" => "anthropic:claude-haiku-4-5",
    "claude-haiku-4-5" => "anthropic:claude-haiku-4-5",
    "claude_sonnet" => "anthropic:claude-sonnet-4-6",
    "claude-sonnet-4-6" => "anthropic:claude-sonnet-4-6",
    "claude_opus" => "anthropic:claude-opus-4-6",
    "claude-opus-4-6" => "anthropic:claude-opus-4-6"
  }

  @impl true
  def complete(model, system_prompt, user_text, _opts \\ []) do
    model_spec = resolve_model(model)

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_text}
    ]

    case ReqLLM.generate_text(model_spec, messages) do
      {:ok, response} -> {:ok, ReqLLM.Response.text(response)}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  @impl true
  def complete_with_tools(model, system_prompt, user_text, tools, _opts \\ []) do
    model_spec = resolve_model(model)

    context =
      ReqLLM.Context.new([
        ReqLLM.Context.system(system_prompt),
        ReqLLM.Context.user(user_text)
      ])

    run_agent_loop(model_spec, context, tools, 0, [])
  end

  @impl true
  def configured? do
    key = ReqLLM.get_key(:anthropic_api_key) || System.get_env("ANTHROPIC_API_KEY")
    key != nil and key != ""
  end

  def tiers, do: ~w(claude_haiku claude_sonnet claude_opus)

  defp resolve_model(model) do
    Map.get(@model_ids, model, "anthropic:#{model}")
  end

  @max_tool_iterations 5

  defp run_agent_loop(_model_spec, _context, _tools, iter, tool_log) when iter >= @max_tool_iterations do
    Logger.warning("[Claude] Max iterations (#{@max_tool_iterations}) reached")
    {:error, :max_iterations_exceeded, tool_log}
  end

  defp run_agent_loop(model_spec, context, tools, iter, tool_log) do
    t0 = System.monotonic_time(:millisecond)
    Logger.debug("[Claude] → #{model_spec} iter=#{iter} tools=#{length(tools)}")

    case ReqLLM.generate_text(model_spec, context, tools: tools) do
      {:ok, response} ->
        ms = System.monotonic_time(:millisecond) - t0

        case ReqLLM.Response.classify(response) do
          %{type: :final_answer, text: text} ->
            Logger.info("[Claude] ✓ #{model_spec} #{ms}ms after #{iter} iter(s), #{length(tool_log)} tool call(s)")
            {:ok, text, tool_log}

          %{type: :tool_calls, tool_calls: calls} ->
            Logger.debug("[Claude] #{model_spec} #{ms}ms — #{length(calls)} tool call(s) at iter #{iter}")
            {next_context, new_entries} = execute_tools_with_log(response.context, calls, tools)

            Enum.each(new_entries, fn %{tool: name, output: out} ->
              Logger.debug("[Claude] tool #{name} → #{String.slice(to_string(out), 0, 120)}")
            end)

            run_agent_loop(model_spec, next_context, tools, iter + 1, tool_log ++ new_entries)
        end

      {:error, reason} ->
        ms = System.monotonic_time(:millisecond) - t0
        Logger.warning("[Claude] ✗ #{model_spec} failed after #{ms}ms: #{inspect(reason)}")
        {:error, inspect(reason), tool_log}
    end
  rescue
    e ->
      Logger.error("[Claude] exception in agent loop: #{Exception.message(e)}")
      {:error, Exception.message(e), tool_log}
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

  defp extract_call_args(%ReqLLM.ToolCall{function: %{arguments: args}}) when is_binary(args),
    do: Jason.decode!(args)

  defp extract_call_args(%ReqLLM.ToolCall{function: %{arguments: args}}), do: args
  defp extract_call_args(%{arguments: args}) when is_binary(args), do: Jason.decode!(args)
  defp extract_call_args(%{arguments: args}), do: args
  defp extract_call_args(_), do: %{}
end
