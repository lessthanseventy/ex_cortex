defmodule ExCortex.LLM.Ollama do
  @moduledoc "Ollama LLM provider."
  @behaviour ExCortex.LLM

  alias ExCortex.Core.LLM.Ollama

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @max_tool_iterations 15
  @empty_threshold 3
  @max_tools_per_turn 15

  @impl true
  def complete(model, system_prompt, user_text, opts \\ []) do
    ollama = client(opts)
    chain = Keyword.get(opts, :fallback_chain, Application.get_env(:ex_cortex, :model_fallback_chain, []))
    models = fallback_models_for(model, chain)
    history = opts |> Keyword.get(:history, []) |> normalize_history(:atom)

    messages =
      [%{role: :system, content: system_prompt}] ++
        history ++
        [%{role: :user, content: user_text}]

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
              ExCortex.AppTelemetry.record_llm_call(m, ms, :ok)
              {:halt, {:ok, text}}

            {:error, reason} ->
              ms = System.monotonic_time(:millisecond) - t0
              Logger.warning("[Ollama] ✗ #{m} failed after #{ms}ms: #{inspect(reason)}")
              ExCortex.AppTelemetry.record_llm_call(m, ms, {:error, reason})
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
    chain = Keyword.get(opts, :fallback_chain, Application.get_env(:ex_cortex, :model_fallback_chain, []))
    models = fallback_models_for(model, chain)
    ollama_tools = Enum.map(tools, &ReqLLM.Schema.to_openai_format/1)
    history = opts |> Keyword.get(:history, []) |> normalize_history(:string)

    messages =
      [%{role: "system", content: system_prompt}] ++
        history ++
        [%{role: "user", content: user_text}]

    max_iter = Keyword.get(opts, :max_tool_iterations, @max_tool_iterations)

    dangerous_tool_mode = Keyword.get(opts, :dangerous_tool_mode, "execute")
    rumination_id = Keyword.get(opts, :rumination_id)

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
        opts: [dangerous_tool_mode: dangerous_tool_mode, rumination_id: rumination_id, max_iter: max_iter]
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
    ExCortex.AppTelemetry.record_llm_call(m, ms, :ok)
    {:halt, {:ok, msg}}
  end

  defp handle_chat_response({:ok, %{status: status, body: body}}, m, t0, _iter) do
    ms = System.monotonic_time(:millisecond) - t0
    Logger.warning("[Ollama] ✗ #{m} failed after #{ms}ms: #{inspect({:ollama_error, status, body})}")
    ExCortex.AppTelemetry.record_llm_call(m, ms, {:error, {:ollama_error, status}})

    if tool_call_incompatible?(body),
      do: Logger.warning("[Ollama] Skipping #{m} for tool-call loop (incompatible message format)")

    {:cont, {:error, :all_models_failed}}
  end

  defp handle_chat_response({:error, reason}, m, t0, _iter) do
    ms = System.monotonic_time(:millisecond) - t0
    Logger.warning("[Ollama] ✗ #{m} failed after #{ms}ms: #{inspect(reason)}")
    ExCortex.AppTelemetry.record_llm_call(m, ms, {:error, reason})
    {:cont, {:error, :all_models_failed}}
  end

  defp execute_tool_calls(calls, tools, breaker_state, opts) do
    middleware = Keyword.get(opts, :middleware, [])

    Enum.reduce(calls, {[], [], breaker_state}, fn call, {msgs, log, bs} ->
      {name, args} = extract_call(call)

      {output, log_entry, new_bs} =
        ExCortex.LLM.ToolExecutor.execute(name, args, tools, bs,
          dangerous_tool_mode: Keyword.get(opts, :dangerous_tool_mode, "execute"),
          rumination_id: Keyword.get(opts, :rumination_id),
          middleware: middleware
        )

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
  def stream_complete(model, system_prompt, user_text, opts \\ []) do
    ollama = client(opts)
    history = opts |> Keyword.get(:history, []) |> normalize_history(:atom)

    messages =
      [%{role: :system, content: system_prompt}] ++
        history ++
        [%{role: :user, content: user_text}]

    body = Jason.encode!(%{model: model, messages: messages, stream: true})
    headers = if ollama.api_key, do: [{"authorization", "Bearer #{ollama.api_key}"}], else: []
    headers = [{"content-type", "application/json"} | headers]

    req = Req.new(base_url: ollama.base_url)

    case Req.post(req,
           url: "/api/chat",
           body: body,
           headers: headers,
           into: :self,
           receive_timeout: 120_000
         ) do
      {:ok, resp} ->
        ref = resp.body

        stream =
          Stream.resource(
            fn -> ref end,
            fn ref ->
              receive do
                {^ref, {:data, data}} ->
                  {parse_ollama_chunks(data), ref}

                {^ref, :done} ->
                  {:halt, ref}
              after
                60_000 -> {:halt, ref}
              end
            end,
            fn _ref -> :ok end
          )

        {:ok, stream}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_ollama_chunks(data) do
    data
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, %{"done" => true}} -> [{:done, ""}]
        {:ok, %{"message" => %{"content" => c}}} -> [{:token, c}]
        _ -> []
      end
    end)
  end

  @impl true
  def configured? do
    url = ExCortex.Settings.resolve(:ollama_url, env_var: "OLLAMA_URL", default: "http://127.0.0.1:11434")
    url != nil and url != ""
  end

  @doc "Build ordered list of models to try: assigned model first, then fallback chain (deduped)."
  def fallback_models_for(model, chain) do
    [model | Enum.reject(chain, &(&1 == model))]
  end

  @doc "Returns true if a tool output is empty or an empty list. Tool errors are NOT empty — they mean the tool ran but the specific call failed, which shouldn't trip the breaker."
  def empty_result?(output) when is_binary(output) do
    trimmed = String.trim(output)

    trimmed == "" or
      trimmed == "[]" or
      trimmed == "[]\n" or
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

  # Normalize conversation history messages to the role format the caller needs.
  # `complete` uses atom roles (:user, :assistant), `complete_with_tools` uses string roles.
  defp normalize_history(history, role_type) do
    Enum.map(history, fn msg ->
      role =
        case {msg[:role] || msg["role"], role_type} do
          {"user", :atom} -> :user
          {"assistant", :atom} -> :assistant
          {role, :atom} when is_atom(role) -> role
          {role, :string} when is_binary(role) -> role
          {role, :string} when is_atom(role) -> Atom.to_string(role)
          {role, :atom} when is_binary(role) -> String.to_existing_atom(role)
        end

      %{role: role, content: msg[:content] || msg["content"] || ""}
    end)
  end

  defp client(opts) do
    url =
      Keyword.get(
        opts,
        :url,
        ExCortex.Settings.resolve(:ollama_url, env_var: "OLLAMA_URL", default: "http://127.0.0.1:11434")
      )

    api_key = Keyword.get(opts, :api_key, ExCortex.Settings.resolve(:ollama_api_key, env_var: "OLLAMA_API_KEY"))
    Ollama.new(base_url: url, api_key: api_key)
  end
end
