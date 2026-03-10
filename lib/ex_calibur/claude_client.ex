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

        run_agent_loop(model_spec, context, tools, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Private — agent loop
  # ---------------------------------------------------------------------------

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
