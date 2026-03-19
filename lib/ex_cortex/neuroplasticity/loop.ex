defmodule ExCortex.Neuroplasticity.Loop do
  @moduledoc """
  Retrospective analysis: after a step run completes, optionally asks Claude
  to review the verdict trace and suggest improvements as Proposals.

  Memory-informed: queries past run engrams and previous proposals for context
  before generating new proposals.

  Usage:
    Loop.retrospect(step, impulse)
    # => {:ok, [%Proposal{}, ...]}  (proposals created)
    # => {:error, reason}
  """

  import Ecto.Query

  alias ExCortex.ClaudeClient
  alias ExCortex.Memory
  alias ExCortex.Repo
  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Proposal
  alias ExCortex.Ruminations.Synapse

  require Logger

  @system_prompt """
  You are a learning system that reviews AI evaluation step results and suggests
  improvements to make future runs more accurate and efficient.

  You have access to memory from past runs and previous proposals. Use this context
  to avoid repeating rejected proposals and to build on successful patterns.

  Given a step definition, a run trace, and historical context, propose up to 3 concrete changes.
  Each proposal must be one of: roster_change, schedule_change, prompt_change, other.

  Format each proposal as:

  PROPOSAL
  TYPE: roster_change | schedule_change | prompt_change | other
  DESCRIPTION: one sentence describing the change
  DETAILS: specific change in plain text (e.g. "Change 'who' from 'all' to 'master'")
  END

  Only propose changes that would meaningfully improve accuracy or efficiency.
  If the run went well and no changes are needed, output nothing.
  Do NOT re-propose changes that were previously rejected.
  """

  @doc """
  Run a retrospective on a completed step run and create Proposals.
  Skips silently if Claude is not configured.
  """
  def retrospect(%Synapse{} = step, impulse) do
    if ClaudeClient.configured?() do
      do_retrospect(step, impulse)
    else
      {:ok, []}
    end
  end

  defp do_retrospect(step, impulse) do
    memory_context = gather_memory_context(step)
    user_text = build_prompt(step, impulse, memory_context)

    case ClaudeClient.complete("claude_haiku", @system_prompt, user_text) do
      {:ok, response} ->
        proposals = parse_proposals(response, step, impulse)
        created = Enum.flat_map(proposals, &maybe_create/1)
        {:ok, created}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp gather_memory_context(step) do
    # Query past run engrams for this step's rumination
    step_tag = step.name |> String.downcase() |> String.replace(~r/\s+/, "-")
    past_runs = Memory.query(step_tag, tier: :L0, limit: 5)

    past_runs_text =
      case past_runs do
        [] ->
          ""

        runs ->
          lines =
            Enum.map_join(runs, "\n", fn e ->
              "- #{e.title}: #{e.impression || "(no summary)"}"
            end)

          "## Past Runs\n#{lines}"
      end

    # Query previous proposals for this synapse
    past_proposals =
      Repo.all(
        from p in Proposal,
          where: p.synapse_id == ^step.id,
          order_by: [desc: p.inserted_at],
          limit: 10
      )

    proposals_text =
      case past_proposals do
        [] ->
          ""

        proposals ->
          lines =
            Enum.map_join(proposals, "\n", fn p ->
              "- [#{p.status}] #{p.type}: #{p.description}"
            end)

          "## Previous Proposals\n#{lines}"
      end

    [past_runs_text, proposals_text]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp build_prompt(step, impulse, memory_context) do
    results = impulse.results || %{}
    verdict = results["verdict"] || "unknown"

    steps =
      (results["steps"] || [])
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {s, i} ->
        neurons =
          Enum.map_join(s["results"] || [], "\n", fn r ->
            "  - #{r["neuron"]}: #{r["verdict"]} (#{r["confidence"]})"
          end)

        "Step #{i} (#{s["who"]} · #{s["how"]}): #{s["verdict"]}\n#{neurons}"
      end)

    memory_section = if memory_context == "", do: "", else: "\n\n#{memory_context}"

    """
    Step: #{step.name}
    Trigger: #{step.trigger}
    Roster: #{inspect(step.roster)}

    Run verdict: #{verdict}
    Run input (truncated): #{String.slice(impulse.input || "", 0, 300)}

    Trace:
    #{steps}#{memory_section}
    """
  end

  defp parse_proposals(text, step, impulse) do
    text
    |> String.split("PROPOSAL", trim: true)
    |> Enum.drop(1)
    |> Enum.map(fn block ->
      type = extract_field(block, "TYPE")
      description = extract_field(block, "DESCRIPTION")
      details = extract_field(block, "DETAILS")

      if type && description do
        %{
          synapse_id: step.id,
          daydream_id: impulse.id,
          type: normalize_type(type),
          description: description,
          details: %{"suggestion" => details || ""},
          status: "pending"
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_field(text, field) do
    case Regex.run(~r/#{field}:\s*(.+)/i, text) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  defp normalize_type(type) do
    type = String.downcase(String.trim(type))

    if type in ["roster_change", "schedule_change", "prompt_change", "other"],
      do: type,
      else: "other"
  end

  defp maybe_create(attrs) do
    case Ruminations.create_proposal(attrs) do
      {:ok, proposal} -> [proposal]
      {:error, _} -> []
    end
  end
end
