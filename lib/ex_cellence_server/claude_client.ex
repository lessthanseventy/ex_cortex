defmodule ExCellenceServer.ClaudeClient do
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
end
