defmodule ExCellenceServer.QuestRunner do
  @moduledoc """
  Runs a Quest's roster against input text, returning a trace of verdicts.

  ## Roster step format
    %{
      "who"         => "all" | "apprentice" | "journeyman" | "master" | "team:X" | member_id | "claude_haiku" | "claude_sonnet" | "claude_opus",
      "when"        => "parallel" | "sequential",
      "how"         => "consensus" | "solo" | "majority",
      "escalate_on" => "never" | "always" | %{"type" => "verdict", "values" => [...]} | %{"type" => "confidence", "threshold" => float}
    }

  ## Return value
    {:ok, %{verdict: "pass"|"warn"|"fail", steps: [step_trace, ...]}}
    {:error, reason}
  """

  import Ecto.Query

  alias Excellence.LLM.Ollama
  alias Excellence.Schemas.Member
  alias ExCellenceServer.ClaudeClient
  alias ExCellenceServer.ContextProviders.ContextProvider
  alias ExCellenceServer.Repo

  @verdict_order %{"fail" => 0, "warn" => 1, "abstain" => 2, "pass" => 3}

  @doc """
  Run a quest roster against `input_text`.
  Accepts either a `Quest` struct or just a bare roster list.
  Returns `{:ok, result}` or `{:error, reason}`.
  """
  def run(quest, input_text) when is_struct(quest) do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"
    run(quest.roster, augmented)
  end

  def run(roster, input_text) when is_list(roster) do
    ollama_url = Application.get_env(:ex_cellence_server, :ollama_url, "http://127.0.0.1:11434")
    ollama = Ollama.new(base_url: ollama_url)

    {steps, final_verdict} =
      Enum.reduce_while(roster, {[], nil}, fn step, {traces, _prev_verdict} ->
        members = resolve_members(step["who"])

        step_results = run_step(members, step["how"], input_text, ollama)

        step_verdict = aggregate(step_results, step["how"])

        trace = %{
          who: step["who"],
          how: step["how"],
          results: step_results,
          verdict: step_verdict
        }

        if should_escalate?(step["escalate_on"], step_verdict) do
          {:halt, {traces ++ [trace], step_verdict}}
        else
          {:cont, {traces ++ [trace], step_verdict}}
        end
      end)

    {:ok, %{verdict: final_verdict || "pass", steps: steps}}
  end

  # ---------------------------------------------------------------------------
  # Member resolution
  # ---------------------------------------------------------------------------

  defp resolve_members("all") do
    from(m in Member, where: m.type == "role" and m.status == "active")
    |> Repo.all()
    |> Enum.map(&member_to_runner_spec/1)
  end

  defp resolve_members("apprentice"), do: resolve_by_rank("apprentice")

  defp resolve_members("journeyman"), do: resolve_by_rank("journeyman")

  defp resolve_members("master"), do: resolve_by_rank("master")

  defp resolve_members("team:" <> team) do
    from(m in Member,
      where: m.type == "role" and m.status == "active" and m.team == ^team
    )
    |> Repo.all()
    |> Enum.map(&member_to_runner_spec/1)
  end

  defp resolve_members(claude_tier) when claude_tier in ["claude_haiku", "claude_sonnet", "claude_opus"] do
    [%{type: :claude, tier: claude_tier, name: claude_tier, system_prompt: nil}]
  end

  defp resolve_members(member_id) when is_binary(member_id) do
    case Repo.get(Member, member_id) do
      nil -> []
      m -> [member_to_runner_spec(m)]
    end
  end

  defp resolve_by_rank(rank) do
    from(m in Member,
      where:
        m.type == "role" and m.status == "active" and
          fragment("config->>'rank' = ?", ^rank)
    )
    |> Repo.all()
    |> Enum.map(&member_to_runner_spec/1)
  end

  defp member_to_runner_spec(db) do
    %{
      type: :ollama,
      model: db.config["model"] || "phi4-mini",
      system_prompt: db.config["system_prompt"] || "",
      name: db.name
    }
  end

  # ---------------------------------------------------------------------------
  # Running a step
  # ---------------------------------------------------------------------------

  defp run_step(members, _how, input_text, ollama) do
    Enum.map(members, fn member ->
      result = call_member(member, input_text, ollama)
      Map.put(result, :member, member.name)
    end)
  end

  defp call_member(%{type: :claude, tier: tier, system_prompt: system_prompt}, input_text, _ollama) do
    prompt = system_prompt || default_claude_prompt()

    case ClaudeClient.complete(tier, prompt, input_text) do
      {:ok, text} -> parse_verdict(text)
      {:error, _} -> %{verdict: "abstain", confidence: 0.0, reason: "Claude API error"}
    end
  end

  defp call_member(%{type: :ollama, model: model, system_prompt: system_prompt}, input_text, ollama) do
    messages = [
      %{role: :system, content: system_prompt},
      %{role: :user, content: input_text}
    ]

    case Ollama.chat(ollama, model, messages) do
      {:ok, %{content: text}} -> parse_verdict(text)
      {:ok, text} when is_binary(text) -> parse_verdict(text)
      _ -> %{verdict: "abstain", confidence: 0.0, reason: "Ollama error"}
    end
  end

  # ---------------------------------------------------------------------------
  # Verdict parsing
  # ---------------------------------------------------------------------------

  defp parse_verdict(text) do
    verdict =
      case Regex.run(~r/ACTION:\s*(pass|warn|fail|abstain)/i, text) do
        [_, v] -> String.downcase(v)
        _ -> "abstain"
      end

    confidence =
      case Regex.run(~r/CONFIDENCE:\s*([0-9.]+)/i, text) do
        [_, c] -> String.to_float(c)
        _ -> 0.5
      end

    reason =
      case Regex.run(~r/REASON:\s*(.+)/is, text) do
        [_, r] -> String.trim(r)
        _ -> ""
      end

    %{verdict: verdict, confidence: confidence, reason: reason}
  end

  # ---------------------------------------------------------------------------
  # Aggregation
  # ---------------------------------------------------------------------------

  defp aggregate([], _), do: "abstain"

  defp aggregate(results, "solo") do
    results |> List.first() |> Map.get(:verdict, "abstain")
  end

  defp aggregate(results, "consensus") do
    verdicts = Enum.map(results, & &1.verdict)
    if Enum.uniq(verdicts) == [hd(verdicts)], do: hd(verdicts), else: worst_verdict(verdicts)
  end

  defp aggregate(results, _majority) do
    verdicts = Enum.map(results, & &1.verdict)
    verdicts |> Enum.frequencies() |> Enum.max_by(fn {_, count} -> count end) |> elem(0)
  end

  defp worst_verdict(verdicts) do
    Enum.min_by(verdicts, &Map.get(@verdict_order, &1, 2))
  end

  # ---------------------------------------------------------------------------
  # Escalation
  # ---------------------------------------------------------------------------

  defp should_escalate?("always", _verdict), do: true
  defp should_escalate?("never", _verdict), do: false

  defp should_escalate?(%{"type" => "verdict", "values" => values}, verdict) do
    verdict in values
  end

  defp should_escalate?(%{"type" => "confidence", "threshold" => _threshold}, _verdict) do
    # Per-result confidence gating is handled by the caller; step-level always passes
    false
  end

  defp should_escalate?(_, _), do: false

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp default_claude_prompt do
    """
    You are a careful evaluator. Review the provided text and give your assessment.

    Respond with:
    ACTION: pass | warn | fail | abstain
    CONFIDENCE: 0.0-1.0
    REASON: your reasoning
    """
  end
end
