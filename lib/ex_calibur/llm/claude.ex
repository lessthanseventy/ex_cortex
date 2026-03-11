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

    run_agent_loop(model_spec, context, tools, 0)
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

  defp run_agent_loop(_model_spec, _context, _tools, iter) when iter >= @max_tool_iterations do
    {:error, :max_iterations_exceeded}
  end

  defp run_agent_loop(model_spec, context, tools, iter) do
    case ReqLLM.generate_text(model_spec, context, tools: tools) do
      {:ok, response} ->
        case ReqLLM.Response.classify(response) do
          %{type: :final_answer, text: text} ->
            {:ok, text}

          %{type: :tool_calls, tool_calls: calls} ->
            next_context =
              ReqLLM.Context.execute_and_append_tools(response.context, calls, tools)

            run_agent_loop(model_spec, next_context, tools, iter + 1)
        end

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
