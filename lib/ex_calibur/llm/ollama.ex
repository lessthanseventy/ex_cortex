defmodule ExCalibur.LLM.Ollama do
  @moduledoc "Ollama LLM provider."
  @behaviour ExCalibur.LLM

  alias Excellence.LLM.Ollama

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @max_tool_iterations 15
  @empty_threshold 3

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
              {:halt, {:ok, text}}

            {:error, reason} ->
              ms = System.monotonic_time(:millisecond) - t0
              Logger.warning("[Ollama] ✗ #{m} failed after #{ms}ms: #{inspect(reason)}")
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

    Tracer.with_span "llm.complete_with_tools", %{
      attributes: %{
        "llm.provider" => "ollama",
        "llm.model" => model,
        "llm.tool_count" => length(tools),
        "llm.input_bytes" => byte_size(user_text)
      }
    } do
      run_tool_loop(ollama, models, messages, tools, ollama_tools, 0, [], %{}, max_iter)
    end
  end

  defp run_tool_loop(_ollama, _models, messages, _tools, _ollama_tools, iter, tool_log, _breaker_state, max_iter)
       when iter >= max_iter do
    text = last_assistant_text(messages)
    Logger.warning("[Ollama] Max tool iterations (#{max_iter}) reached")
    {:ok, text, tool_log}
  end

  defp run_tool_loop(ollama, models, messages, tools, ollama_tools, iter, tool_log, breaker_state, max_iter) do
    result =
      Enum.reduce_while(models, {:error, :all_models_failed}, fn m, _acc ->
        t0 = System.monotonic_time(:millisecond)
        Logger.debug("[Ollama] → #{m} iter=#{iter} tools=#{length(tools)}")

        body = %{model: m, messages: messages, tools: ollama_tools, stream: false}

        headers =
          if ollama.api_key, do: [{"authorization", "Bearer #{ollama.api_key}"}], else: []

        case Req.post(ollama.base_url <> "/api/chat",
               json: body,
               headers: headers,
               connect_options: [timeout: 10_000],
               receive_timeout: ollama.timeout
             ) do
          {:ok, %{status: 200, body: %{"message" => msg}}} ->
            ms = System.monotonic_time(:millisecond) - t0
            Logger.debug("[Ollama] ✓ #{m} #{ms}ms iter=#{iter}")
            {:halt, {:ok, msg}}

          {:ok, %{status: status, body: body}} ->
            ms = System.monotonic_time(:millisecond) - t0

            reason = {:ollama_error, status, body}
            Logger.warning("[Ollama] ✗ #{m} failed after #{ms}ms: #{inspect(reason)}")

            if tool_call_incompatible?(body) do
              Logger.warning("[Ollama] Skipping #{m} for tool-call loop (incompatible message format)")
            end

            {:cont, {:error, :all_models_failed}}

          {:error, reason} ->
            ms = System.monotonic_time(:millisecond) - t0
            Logger.warning("[Ollama] ✗ #{m} failed after #{ms}ms: #{inspect(reason)}")
            {:cont, {:error, :all_models_failed}}
        end
      end)

    case result do
      {:ok, %{"tool_calls" => calls} = msg} when is_list(calls) and calls != [] ->
        assistant_msg = %{
          role: "assistant",
          content: Map.get(msg, "content", ""),
          tool_calls: calls
        }

        {tool_msgs, new_entries, new_bs} = execute_tool_calls(calls, tools, breaker_state)
        new_messages = messages ++ [assistant_msg] ++ tool_msgs

        run_tool_loop(
          ollama,
          models,
          new_messages,
          tools,
          ollama_tools,
          iter + 1,
          tool_log ++ new_entries,
          new_bs,
          max_iter
        )

      {:ok, %{"content" => text}} ->
        {:ok, text, tool_log}

      {:error, reason} ->
        {:error, reason, tool_log}
    end
  end

  defp execute_tool_calls(calls, tools, breaker_state) do
    Enum.reduce(calls, {[], [], breaker_state}, fn call, {msgs, log, bs} ->
      name = get_in(call, ["function", "name"])
      args_raw = get_in(call, ["function", "arguments"])

      args =
        case args_raw do
          s when is_binary(s) -> Jason.decode!(s)
          m when is_map(m) -> m
          _ -> %{}
        end

      prior_count = Map.get(bs, name, 0)

      {output, log_entry, new_bs} =
        if prior_count >= @empty_threshold do
          out =
            "Tool #{name} returned empty results #{prior_count} times. Skipping — proceed with available information."

          Logger.debug("[Ollama] circuit breaker: skipping #{name}")
          {out, %{tool: name, input: args, output: out}, bs}
        else
          tool = Enum.find(tools, &(&1.name == name))

          {out, entry} =
            if tool do
              case ReqLLM.Tool.execute(tool, args) do
                {:ok, v} ->
                  o = to_string(v)
                  Logger.debug("[Ollama] tool #{name} → #{String.slice(o, 0, 120)}")
                  {o, %{tool: name, input: args, output: o}}

                {:error, e} ->
                  o = "Error: #{inspect(e)}"
                  {o, %{tool: name, input: args, output: o}}
              end
            else
              o = "Tool #{name} not found"
              {o, %{tool: name, input: args, output: o}}
            end

          case check_circuit_breaker(name, out, bs) do
            {:tripped, updated_bs} -> {out, entry, updated_bs}
            {:ok, updated_bs} -> {out, entry, updated_bs}
          end
        end

      tool_msg = %{role: "tool", content: output}
      {msgs ++ [tool_msg], log ++ [log_entry], new_bs}
    end)
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
    trimmed == "" or trimmed == "[]" or trimmed == "[]\n" or String.starts_with?(trimmed, "Error:")
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
