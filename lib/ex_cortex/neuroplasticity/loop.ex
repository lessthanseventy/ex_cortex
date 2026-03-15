defmodule ExCortex.Neuroplasticity.Loop do
  @moduledoc """
  Retrospective analysis: after a step run completes, optionally asks Claude
  to review the verdict trace and suggest improvements as Proposals.

  Small changes (schedule tweaks, roster tier adjustments) are proposed with
  status "pending" and require user approval from the Cortex.

  Usage:
    Loop.retrospect(step, impulse)
    # => {:ok, [%Proposal{}, ...]}  (proposals created)
    # => {:error, reason}
  """

  alias ExCortex.ClaudeClient
  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Synapse

  @system_prompt """
  You are a learning system that reviews AI evaluation step results and suggests
  improvements to make future runs more accurate and efficient.

  Given a step definition and a run trace, propose up to 3 concrete changes.
  Each proposal must be one of: roster_change, schedule_change, prompt_change, other.

  Format each proposal as:

  PROPOSAL
  TYPE: roster_change | schedule_change | prompt_change | other
  DESCRIPTION: one sentence describing the change
  DETAILS: specific change in plain text (e.g. "Change 'who' from 'all' to 'master'")
  END

  Only propose changes that would meaningfully improve accuracy or efficiency.
  If the run went well and no changes are needed, output nothing.
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
    user_text = build_prompt(step, impulse)

    case ClaudeClient.complete("claude_haiku", @system_prompt, user_text) do
      {:ok, response} ->
        proposals = parse_proposals(response, step, impulse)
        created = Enum.flat_map(proposals, &maybe_create/1)
        {:ok, created}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_prompt(step, impulse) do
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

    """
    Step: #{step.name}
    Trigger: #{step.trigger}
    Roster: #{inspect(step.roster)}

    Run verdict: #{verdict}
    Run input (truncated): #{String.slice(impulse.input || "", 0, 300)}

    Trace:
    #{steps}
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
