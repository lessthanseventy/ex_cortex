defmodule ExCalibur.LLM.Claude do
  @moduledoc "Claude (Anthropic) LLM provider."
  @behaviour ExCalibur.LLM

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

  defp extract_call_args(%ReqLLM.ToolCall{function: %{arguments: args}}) when is_binary(args),
    do: Jason.decode!(args)

  defp extract_call_args(%ReqLLM.ToolCall{function: %{arguments: args}}), do: args
  defp extract_call_args(%{arguments: args}) when is_binary(args), do: Jason.decode!(args)
  defp extract_call_args(%{arguments: args}), do: args
  defp extract_call_args(_), do: %{}
end
