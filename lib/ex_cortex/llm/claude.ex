defmodule ExCortex.LLM.Claude do
  @moduledoc "Claude (Anthropic) LLM provider."
  @behaviour ExCortex.LLM

  alias ExCortex.Ruminations.ImpulseRunner

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @max_tool_iterations 5

  @model_ids %{
    "claude_haiku" => "anthropic:claude-haiku-4-5",
    "claude-haiku-4-5" => "anthropic:claude-haiku-4-5",
    "claude_sonnet" => "anthropic:claude-sonnet-4-6",
    "claude-sonnet-4-6" => "anthropic:claude-sonnet-4-6",
    "claude_opus" => "anthropic:claude-opus-4-6",
    "claude-opus-4-6" => "anthropic:claude-opus-4-6"
  }

  @impl true
  def complete(model, system_prompt, user_text, opts \\ []) do
    model_spec = resolve_model(model)
    history = opts |> Keyword.get(:history, []) |> normalize_history()

    messages =
      [%{role: "system", content: system_prompt}] ++
        history ++
        [%{role: "user", content: user_text}]

    Tracer.with_span "llm.complete", %{
      attributes: %{
        "llm.provider" => "claude",
        "llm.model" => model_spec,
        "llm.input_bytes" => byte_size(user_text)
      }
    } do
      case ReqLLM.generate_text(model_spec, messages) do
        {:ok, response} ->
          text = ReqLLM.Response.text(response)
          Tracer.set_attributes(%{"llm.output_bytes" => byte_size(text), "llm.status" => "ok"})
          {:ok, text}

        {:error, reason} ->
          Tracer.set_attributes(%{"llm.status" => "error"})
          {:error, inspect(reason)}
      end
    end
  end

  @impl true
  def complete_with_tools(model, system_prompt, user_text, tools, opts \\ []) do
    model_spec = resolve_model(model)
    max_iter = Keyword.get(opts, :max_tool_iterations, @max_tool_iterations)
    history = opts |> Keyword.get(:history, []) |> normalize_history()

    history_messages =
      Enum.map(history, fn %{role: role, content: content} ->
        case role do
          "user" -> ReqLLM.Context.user(content)
          "assistant" -> ReqLLM.Context.assistant(content)
          _ -> ReqLLM.Context.user(content)
        end
      end)

    context =
      ReqLLM.Context.new(
        [ReqLLM.Context.system(system_prompt)] ++
          history_messages ++
          [ReqLLM.Context.user(user_text)]
      )

    dangerous_tool_mode = Keyword.get(opts, :dangerous_tool_mode, "execute")
    rumination_id = Keyword.get(opts, :rumination_id)

    Tracer.with_span "llm.complete_with_tools", %{
      attributes: %{
        "llm.provider" => "claude",
        "llm.model" => model_spec,
        "llm.tool_count" => length(tools),
        "llm.input_bytes" => byte_size(user_text)
      }
    } do
      run_agent_loop(model_spec, context, tools, 0, [], %{}, max_iter,
        dangerous_tool_mode: dangerous_tool_mode,
        rumination_id: rumination_id
      )
    end
  end

  @impl true
  def configured? do
    key = ExCortex.Settings.resolve(:anthropic_api_key, env_var: "ANTHROPIC_API_KEY")
    key != nil and key != ""
  end

  def tiers, do: ~w(claude_haiku claude_sonnet claude_opus)

  defp resolve_model(model) do
    Map.get(@model_ids, model, "anthropic:#{model}")
  end

  defp run_agent_loop(_model_spec, _context, _tools, iter, tool_log, _breaker_state, max_iter, _opts)
       when iter >= max_iter do
    Logger.warning("[Claude] Max iterations (#{max_iter}) reached")
    {:error, :max_iterations_exceeded, tool_log}
  end

  defp run_agent_loop(model_spec, context, tools, iter, tool_log, breaker_state, max_iter, opts) do
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

            {next_context, new_entries, new_bs} =
              execute_tools_with_log(response.context, calls, tools, breaker_state, opts)

            Enum.each(new_entries, &log_tool_entry/1)

            run_agent_loop(model_spec, next_context, tools, iter + 1, tool_log ++ new_entries, new_bs, max_iter, opts)
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

  defp execute_tools_with_log(context, calls, tools, breaker_state, opts) do
    dangerous_mode = Keyword.get(opts, :dangerous_tool_mode, "execute")
    rumination_id = Keyword.get(opts, :rumination_id)

    Enum.reduce(calls, {context, [], breaker_state}, fn call, {ctx, log, bs} ->
      {name, id} = extract_call_info(call)
      args = extract_call_args(call)
      {output, result_content, new_bs} = execute_single_call(name, args, tools, bs, dangerous_mode, rumination_id)
      msg = ReqLLM.Context.tool_result(id, name, result_content)
      next_ctx = ReqLLM.Context.append(ctx, msg)
      {next_ctx, log ++ [%{tool: name, input: args, output: output}], new_bs}
    end)
  end

  defp execute_single_call(name, args, tools, bs, dangerous_mode, rumination_id) do
    prior_count = Map.get(bs, name, 0)
    do_execute_call(name, args, tools, bs, dangerous_mode, rumination_id, prior_count)
  end

  defp do_execute_call(name, _args, _tools, bs, _mode, _rumination_id, prior_count) when prior_count >= 3 do
    out = "Tool #{name} returned empty results #{prior_count} times. Skipping — proceed with available information."
    Logger.debug("[Claude] circuit breaker: skipping #{name}")
    {out, out, bs}
  end

  defp do_execute_call(name, args, tools, bs, dangerous_mode, rumination_id, _prior_count) do
    if ImpulseRunner.dangerous?(name) and dangerous_mode != "execute" do
      execute_dangerous_call(name, args, bs, dangerous_mode, rumination_id)
    else
      execute_safe_call(name, args, tools, bs)
    end
  end

  defp execute_dangerous_call(name, args, bs, "dry_run", _rumination_id) do
    out = "DRY RUN: Would have called #{name} with #{Jason.encode!(args)}. No action taken."
    Logger.info("[Claude] dry_run: #{name}")
    {out, out, bs}
  end

  defp execute_dangerous_call(name, args, bs, "intercept", rumination_id) do
    ImpulseRunner.intercept_dangerous_tool(name, args, rumination_id)
    out = "Tool call queued for human approval. Proposal ID: #{rumination_id}. Continue without this result."
    Logger.info("[Claude] intercepted: #{name}")
    {out, out, bs}
  end

  defp execute_safe_call(name, args, tools, bs) do
    tool = Enum.find(tools, &(&1.name == name))

    {_result, out, content} =
      Tracer.with_span "llm.tool_call", %{attributes: %{"tool.name" => name}} do
        r = if tool, do: ReqLLM.Tool.execute(tool, args), else: {:error, "Tool #{name} not found"}

        o =
          case r do
            {:ok, v} -> to_string(v)
            {:error, e} -> "Error: #{inspect(e)}"
          end

        c =
          case r do
            {:ok, v} -> to_string(v)
            {:error, e} -> Jason.encode!(%{error: to_string(e)})
          end

        Tracer.set_attributes(%{
          "tool.status" => if(match?({:ok, _}, r), do: "ok", else: "error"),
          "tool.output_bytes" => byte_size(o)
        })

        {r, o, c}
      end

    case ExCortex.LLM.Ollama.check_circuit_breaker(name, out, bs) do
      {:tripped, updated_bs} -> {out, content, updated_bs}
      {:ok, updated_bs} -> {out, content, updated_bs}
    end
  end

  defp log_tool_entry(%{tool: name, output: out}) do
    Logger.debug("[Claude] tool #{name} → #{String.slice(to_string(out), 0, 120)}")
  end

  defp extract_call_info(%ReqLLM.ToolCall{id: id, function: %{name: name}}), do: {name, id}
  defp extract_call_info(%{name: name, id: id}), do: {name, id}

  defp extract_call_args(%ReqLLM.ToolCall{function: %{arguments: args}}) when is_binary(args), do: Jason.decode!(args)

  defp extract_call_args(%ReqLLM.ToolCall{function: %{arguments: args}}), do: args
  defp extract_call_args(%{arguments: args}) when is_binary(args), do: Jason.decode!(args)
  defp extract_call_args(%{arguments: args}), do: args
  defp extract_call_args(_), do: %{}

  defp normalize_history(history) do
    Enum.map(history, fn msg ->
      role = to_string(msg[:role] || msg["role"] || "user")
      content = msg[:content] || msg["content"] || ""
      %{role: role, content: content}
    end)
  end
end
