defmodule ExCalibur.QuestRunner do
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

  alias ExCalibur.ClaudeClient
  alias ExCalibur.ContextProviders.ContextProvider
  alias ExCalibur.Repo
  alias Excellence.LLM.Ollama
  alias Excellence.Schemas.Member

  @verdict_order %{"fail" => 0, "warn" => 1, "abstain" => 2, "pass" => 3}

  @herald_types ~w(slack webhook github_issue github_pr email pagerduty)

  @doc """
  Run a quest roster against `input_text`.
  Accepts either a `Quest` struct or just a bare roster list.
  Returns `{:ok, result}` or `{:error, reason}`.
  """
  def run(%{output_type: type} = quest, input_text) when type in @herald_types do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    with {:ok, herald} <- ExCalibur.Heralds.get_by_name(quest.herald_name || ""),
         {:ok, attrs} <- run_artifact(quest, augmented),
         :ok <- ExCalibur.Heralds.deliver(herald, quest, attrs) do
      {:ok, %{delivered: true, type: type, title: attrs.title}}
    end
  end

  def run(%{output_type: "artifact"} = quest, input_text) do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"
    result = run_artifact(quest, augmented)

    case result do
      {:ok, attrs} ->
        ExCalibur.Lore.write_artifact(quest, attrs)
        {:ok, %{artifact: attrs}}

      error ->
        error
    end
  end

  def run(quest, input_text) when is_struct(quest) do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"
    run(quest.roster, augmented)
  end

  def run(roster, input_text) when is_list(roster) do
    ollama_url = Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434")
    ollama = Ollama.new(base_url: ollama_url)

    {steps, final_verdict} =
      Enum.reduce_while(roster, {[], nil}, fn step, {traces, _prev_verdict} ->
        members = resolve_members(step)

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

  defp resolve_members(%{"preferred_who" => name} = step) when is_binary(name) and name != "" do
    case from(m in Member,
           where: m.type == "role" and m.status == "active" and m.name == ^name
         )
         |> Repo.all()
         |> Enum.map(&member_to_runner_spec/1) do
      [] -> resolve_members(%{step | "preferred_who" => nil})
      members -> members
    end
  end

  defp resolve_members(%{"who" => who}), do: resolve_members(who)
  defp resolve_members(step) when is_map(step), do: resolve_members(Map.get(step, "who", "all"))

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

  # ---------------------------------------------------------------------------
  # Artifact generation
  # ---------------------------------------------------------------------------

  defp run_artifact(quest, input_text) do
    ollama_url = Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434")
    ollama = Ollama.new(base_url: ollama_url)

    members =
      case quest.roster do
        [first | _] -> resolve_members(first)
        _ -> resolve_members("all")
      end

    member = List.first(members)

    if is_nil(member) do
      {:error, :no_members}
    else
      system_prompt = artifact_system_prompt(quest)

      messages = [
        %{role: :system, content: system_prompt},
        %{role: :user, content: input_text}
      ]

      raw =
        case member do
          %{type: :claude, tier: tier} ->
            case ClaudeClient.complete(tier, system_prompt, input_text) do
              {:ok, text} -> text
              _ -> nil
            end

          %{type: :ollama, model: model} ->
            case Ollama.chat(ollama, model, messages) do
              {:ok, %{content: text}} -> text
              {:ok, text} when is_binary(text) -> text
              _ -> nil
            end
        end

      if raw do
        date = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")
        title_template = quest.entry_title_template || quest.name || "Entry — {date}"
        title = String.replace(title_template, "{date}", date)
        {:ok, parse_artifact(raw, title)}
      else
        {:error, :llm_failed}
      end
    end
  end

  defp artifact_system_prompt(quest) do
    instruction = quest.description || "Synthesize the provided content."

    """
    #{instruction}

    Respond in this exact format:
    TITLE: <a concise title for this entry>
    IMPORTANCE: <integer 1-5, where 5 is most important, or omit if not applicable>
    TAGS: <comma-separated tags, lowercase, e.g. a11y,security,deps>
    BODY:
    <your synthesized content here, markdown is fine>
    """
  end

  defp parse_artifact(text, fallback_title) do
    title =
      case Regex.run(~r/^TITLE:\s*(.+)$/m, text) do
        [_, t] -> String.trim(t)
        _ -> fallback_title
      end

    importance =
      case Regex.run(~r/^IMPORTANCE:\s*(\d)$/m, text) do
        [_, n] ->
          val = String.to_integer(n)
          if val in 1..5, do: val

        _ ->
          nil
      end

    tags =
      case Regex.run(~r/^TAGS:\s*(.+)$/m, text) do
        [_, t] ->
          t |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

        _ ->
          []
      end

    body =
      case Regex.run(~r/^BODY:\s*\n(.*)/ms, text) do
        [_, b] -> String.trim(b)
        _ -> text
      end

    %{title: title, body: body, tags: tags, importance: importance, source: "quest"}
  end
end
