defmodule ExCalibur.LLM.Ollama do
  @moduledoc "Ollama LLM provider."
  @behaviour ExCalibur.LLM

  alias Excellence.LLM.Ollama

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @max_tool_iterations 15
  @empty_threshold 3
  @max_tools_per_turn 3

  @impl true
  def complete(model, system_prompt, user_text, opts \\ []) do
    ollama = client(opts)
    chain = Keyword.get(opts, :fallback_chain, Application.get_env(:ex_calibur, :model_fallback_chain, []))
    models = fallback_models_for(model, chain)

    messages = [
      %{role: :system, content: system_prompt},
      %{role: :user, content: user_text}
    ]

    Tracer.with_span "llm.complete", %{
      attributes: %{
        "llm.provider" => "ollama",
        "llm.model" => model,
        "llm.input_bytes" => byte_size(user_text)
      }
    } do
      result =
        Enum.reduce_while(models, {:error, :all_models_failed}, fn m, acc ->
          t0 = System.monotonic_time(:millisecond)
          Logger.debug("[Ollama] → #{m} (#{byte_size(user_text)}B input)")

          case Ollama.chat(ollama, m, messages) do
            {:ok, text} when is_binary(text) ->
              ms = System.monotonic_time(:millisecond) - t0
              Logger.info("[Ollama] ✓ #{m} #{ms}ms (#{byte_size(text)}B output)")
              ExCalibur.AppTelemetry.record_llm_call(m, ms, :ok)
              {:halt, {:ok, text}}

            {:error, reason} ->
              ms = System.monotonic_time(:millisecond) - t0
              Logger.warning("[Ollama] ✗ #{m} failed after #{ms}ms: #{inspect(reason)}")
              ExCalibur.AppTelemetry.record_llm_call(m, ms, {:error, reason})
              {:cont, acc}

            other ->
              Logger.warning("[Ollama] ✗ #{m} unexpected response: #{inspect(other)}")
              {:cont, acc}
          end
        end)

      case result do
        {:ok, text} ->
          Tracer.set_attributes(%{"llm.output_bytes" => byte_size(text), "llm.status" => "ok"})

        _ ->
          Tracer.set_attributes(%{"llm.status" => "error"})
      end

      result
    end
  end

  @impl true
  def complete_with_tools(model, system_prompt, user_text, tools, opts \\ []) do
    ollama = client(opts)
    chain = Keyword.get(opts, :fallback_chain, Application.get_env(:ex_calibur, :model_fallback_chain, []))
    models = fallback_models_for(model, chain)
    ollama_tools = Enum.map(tools, &ReqLLM.Schema.to_openai_format/1)

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_text}
    ]

    max_iter = Keyword.get(opts, :max_tool_iterations, @max_tool_iterations)

    dangerous_tool_mode = Keyword.get(opts, :dangerous_tool_mode, "execute")
    quest_id = Keyword.get(opts, :quest_id)

    Tracer.with_span "llm.complete_with_tools", %{
      attributes: %{
        "llm.provider" => "ollama",
        "llm.model" => model,
        "llm.tool_count" => length(tools),
        "llm.input_bytes" => byte_size(user_text)
      }
    } do
      conn = %{
        ollama: ollama,
        models: models,
        tools: tools,
        ollama_tools: ollama_tools,
        opts: [dangerous_tool_mode: dangerous_tool_mode, quest_id: quest_id, max_iter: max_iter]
      }

      run_tool_loop(conn, %{messages: messages, iter: 0, tool_log: [], breaker_state: %{}})
    end
  end

  defp run_tool_loop(%{opts: opts} = conn, %{messages: messages, iter: iter, tool_log: tool_log} = state) do
    max_iter = Keyword.get(opts, :max_iter, @max_tool_iterations)

    if iter >= max_iter do
      Logger.warning("[Ollama] Max tool iterations (#{max_iter}) reached")
      {:ok, last_assistant_text(messages), tool_log}
    else
      run_tool_loop_step(conn, state)
    end
  end

  defp run_tool_loop_step(
         %{ollama: ollama, models: models, tools: tools, ollama_tools: ollama_tools, opts: opts} = conn,
         %{messages: messages, iter: iter, tool_log: tool_log, breaker_state: bs} = state
       ) do
    case call_models(ollama, models, ollama_tools, messages, iter) do
      {:ok, %{"tool_calls" => calls} = msg} when is_list(calls) and calls != [] ->
        capped = Enum.take(calls, @max_tools_per_turn)

        if length(calls) > @max_tools_per_turn do
          Logger.warning("[Ollama] capping #{length(calls)} tool calls to #{@max_tools_per_turn} per turn")
        end

        {tool_msgs, new_entries, new_bs} = execute_tool_calls(capped, tools, bs, opts)
        # Use capped (not calls) so assistant message matches the tool results we actually return
        assistant_msg = %{role: "assistant", content: Map.get(msg, "content", ""), tool_calls: capped}

        new_state = %{
          state
          | messages: messages ++ [assistant_msg] ++ tool_msgs,
            iter: iter + 1,
            tool_log: tool_log ++ new_entries,
            breaker_state: new_bs
        }

        run_tool_loop(conn, new_state)

      {:ok, %{"content" => text}} ->
        {:ok, text, tool_log}

      {:error, reason} ->
        {:error, reason, tool_log}
    end
  end

  defp call_models(ollama, models, ollama_tools, messages, iter) do
    Enum.reduce_while(models, {:error, :all_models_failed}, fn m, _acc ->
      t0 = System.monotonic_time(:millisecond)
      Logger.debug("[Ollama] → #{m} iter=#{iter} tools=#{length(ollama_tools)}")
      headers = if ollama.api_key, do: [{"authorization", "Bearer #{ollama.api_key}"}], else: []

      ollama.base_url
      |> Kernel.<>("/api/chat")
      |> Req.post(
        json: %{model: m, messages: messages, tools: ollama_tools, stream: false},
        headers: headers,
        connect_options: [timeout: 10_000],
        receive_timeout: ollama.timeout
      )
      |> handle_chat_response(m, t0, iter)
    end)
  end

  defp handle_chat_response({:ok, %{status: 200, body: %{"message" => msg}}}, m, t0, iter) do
    ms = System.monotonic_time(:millisecond) - t0
    Logger.debug("[Ollama] ✓ #{m} #{ms}ms iter=#{iter}")
    ExCalibur.AppTelemetry.record_llm_call(m, ms, :ok)
    {:halt, {:ok, msg}}
  end

  defp handle_chat_response({:ok, %{status: status, body: body}}, m, t0, _iter) do
    ms = System.monotonic_time(:millisecond) - t0
    Logger.warning("[Ollama] ✗ #{m} failed after #{ms}ms: #{inspect({:ollama_error, status, body})}")
    ExCalibur.AppTelemetry.record_llm_call(m, ms, {:error, {:ollama_error, status}})

    if tool_call_incompatible?(body),
      do: Logger.warning("[Ollama] Skipping #{m} for tool-call loop (incompatible message format)")

    {:cont, {:error, :all_models_failed}}
  end

  defp handle_chat_response({:error, reason}, m, t0, _iter) do
    ms = System.monotonic_time(:millisecond) - t0
    Logger.warning("[Ollama] ✗ #{m} failed after #{ms}ms: #{inspect(reason)}")
    ExCalibur.AppTelemetry.record_llm_call(m, ms, {:error, reason})
    {:cont, {:error, :all_models_failed}}
  end

  defp execute_tool_calls(calls, tools, breaker_state, opts) do
    dangerous_mode = Keyword.get(opts, :dangerous_tool_mode, "execute")
    quest_id = Keyword.get(opts, :quest_id)

    Enum.reduce(calls, {[], [], breaker_state}, fn call, {msgs, log, bs} ->
      {name, args} = extract_call(call)
      {output, log_entry, new_bs} = execute_call(name, args, tools, bs, dangerous_mode, quest_id)
      {msgs ++ [%{role: "tool", content: output}], log ++ [log_entry], new_bs}
    end)
  end

  defp extract_call(call) do
    name = get_in(call, ["function", "name"])

    args =
      case get_in(call, ["function", "arguments"]) do
        s when is_binary(s) -> Jason.decode!(s)
        m when is_map(m) -> m
        _ -> %{}
      end

    {name, args}
  end

  defp execute_call(name, args, tools, bs, dangerous_mode, quest_id) do
    prior_count = Map.get(bs, name, 0)

    cond do
      prior_count >= @empty_threshold ->
        out = unavailable_message(name, tools)
        Logger.debug("[Ollama] circuit breaker: skipping #{name}")
        ExCalibur.AppTelemetry.record_circuit_breaker(name)
        {out, %{tool: name, input: args, output: out}, bs}

      is_nil(Enum.find(tools, &(&1.name == name))) and not ExCalibur.StepRunner.dangerous?(name) ->
        # Unknown tool — trip the breaker immediately so it's skipped on all future calls
        out = unavailable_message(name, tools)
        Logger.warning("[Ollama] unknown tool called: #{name}")
        {out, %{tool: name, input: %{}, output: out}, Map.put(bs, name, @empty_threshold)}

      true ->
        {out, entry} = execute_or_intercept_tool(name, args, tools, dangerous_mode, quest_id)

        case check_circuit_breaker(name, out, bs) do
          {:tripped, updated_bs} -> {out, entry, updated_bs}
          {:ok, updated_bs} -> {out, entry, updated_bs}
        end
    end
  end

  defp execute_or_intercept_tool(name, args, tools, dangerous_mode, quest_id) do
    if ExCalibur.StepRunner.dangerous?(name) and dangerous_mode != "execute" do
      intercept_dangerous_call(name, args, dangerous_mode, quest_id)
    else
      run_tool(name, args, Enum.find(tools, &(&1.name == name)))
    end
  end

  defp intercept_dangerous_call(name, args, "dry_run", _quest_id) do
    out = "DRY RUN: Would have called #{name} with #{Jason.encode!(args)}. No action taken."
    Logger.info("[Ollama] dry_run: #{name}")
    {out, %{tool: name, input: args, output: out}}
  end

  defp intercept_dangerous_call(name, args, "intercept", quest_id) do
    ExCalibur.StepRunner.intercept_dangerous_tool(name, args, quest_id)
    out = "Tool call queued for human approval. Proposal ID: #{quest_id}. Continue without this result."
    Logger.info("[Ollama] intercepted: #{name}")
    {out, %{tool: name, input: args, output: out}}
  end

  defp run_tool(name, _args, nil) do
    o = "Tool '#{name}' is not available in this step. Stop calling it."
    Logger.warning("[Ollama] unknown tool called: #{name}")
    {o, %{tool: name, input: %{}, output: o}}
  end

  defp run_tool(name, args, tool) do
    case ReqLLM.Tool.execute(tool, args) do
      {:ok, v} ->
        o = to_string(v)
        Logger.debug("[Ollama] tool #{name} → #{String.slice(o, 0, 120)}")
        {o, %{tool: name, input: args, output: o}}

      {:error, e} ->
        o = "Error: #{inspect(e)}"
        {o, %{tool: name, input: args, output: o}}
    end
  end

  # Build a directive unavailability message that names the tools the model SHOULD use instead.
  defp unavailable_message(blocked_name, tools) do
    available = Enum.map(tools, & &1.name)

    hint =
      cond do
        "run_sandbox" in available ->
          " Call run_sandbox with 'mix credo --all' or 'mix test' to analyze the codebase."

        available != [] ->
          " Your available tools are: #{Enum.join(available, ", ")}. Use those instead."

        true ->
          " Stop calling tools and write your findings based on what you already know."
      end

    "Tool '#{blocked_name}' is not available in this step.#{hint}"
  end

  defp tool_call_incompatible?(body) when is_binary(body), do: String.contains?(body, "roles must alternate")

  defp tool_call_incompatible?(%{"error" => msg}) when is_binary(msg), do: String.contains?(msg, "roles must alternate")

  defp tool_call_incompatible?(_), do: false

  defp last_assistant_text(messages) do
    messages
    |> Enum.filter(&(Map.get(&1, :role) == "assistant"))
    |> List.last()
    |> then(fn
      nil -> ""
      msg -> Map.get(msg, :content, "")
    end)
  end

  @impl true
  def configured? do
    url = Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434")
    url != nil and url != ""
  end

  @doc "Build ordered list of models to try: assigned model first, then fallback chain (deduped)."
  def fallback_models_for(model, chain) do
    [model | Enum.reject(chain, &(&1 == model))]
  end

  @doc "Returns true if a tool output is empty, an empty list, or an error."
  def empty_result?(output) when is_binary(output) do
    trimmed = String.trim(output)

    trimmed == "" or
      trimmed == "[]" or
      trimmed == "[]\n" or
      String.starts_with?(trimmed, "Error:") or
      String.contains?(trimmed, "is not available in this step")
  end

  def empty_result?(_), do: true

  @doc "Check whether a tool has tripped its circuit breaker after consecutive empty results."
  def check_circuit_breaker(tool_name, output, breaker_state) do
    if empty_result?(output) do
      count = Map.get(breaker_state, tool_name, 0) + 1

      if count >= @empty_threshold do
        {:tripped, Map.put(breaker_state, tool_name, count)}
      else
        {:ok, Map.put(breaker_state, tool_name, count)}
      end
    else
      {:ok, Map.put(breaker_state, tool_name, 0)}
    end
  end

  defp client(opts) do
    url = Keyword.get(opts, :url, Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434"))
    api_key = Keyword.get(opts, :api_key, Application.get_env(:ex_calibur, :ollama_api_key))
    Ollama.new(base_url: url, api_key: api_key)
  end
end
