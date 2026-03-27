defmodule ExCortex.Neuroplasticity.ProposalExecutor do
  @moduledoc """
  Applies approved proposals to synapses.

  When a user approves a proposal, this module interprets the proposal type
  and applies the change to the target synapse.
  """

  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Proposal

  require Logger

  @doc """
  Apply an approved proposal. Returns {:ok, proposal} with status "applied"
  or {:ok, proposal} with status "failed" and a reason.
  """
  def apply(%Proposal{status: "approved", type: type} = proposal) do
    synapse = Ruminations.get_synapse!(proposal.synapse_id)
    suggestion = get_in(proposal.details, ["suggestion"]) || ""

    result =
      case type do
        "roster_change" -> apply_roster_change(synapse, suggestion)
        "prompt_change" -> apply_prompt_change(synapse, suggestion)
        "schedule_change" -> apply_schedule_change(synapse, suggestion)
        _ -> {:skip, "Proposal type '#{type}' requires manual application"}
      end

    case result do
      {:ok, _synapse} ->
        Logger.info("[ProposalExecutor] Applied #{type} to synapse #{synapse.id} (#{synapse.name})")
        Ruminations.update_proposal(proposal, %{status: "applied", applied_at: DateTime.utc_now()})

      {:skip, reason} ->
        Logger.info("[ProposalExecutor] Skipped #{type} for synapse #{synapse.id}: #{reason}")
        Ruminations.update_proposal(proposal, %{status: "approved", result: reason})

      {:error, reason} ->
        Logger.warning("[ProposalExecutor] Failed to apply #{type} to synapse #{synapse.id}: #{inspect(reason)}")
        Ruminations.update_proposal(proposal, %{status: "failed", result: inspect(reason)})
    end
  rescue
    e ->
      Logger.error("[ProposalExecutor] Error applying proposal #{proposal.id}: #{Exception.message(e)}")
      Ruminations.update_proposal(proposal, %{status: "failed", result: Exception.message(e)})
  end

  def apply(%Proposal{} = proposal) do
    {:ok, proposal}
  end

  # Roster changes: parse "Change 'who' from 'all' to 'master'" style suggestions
  defp apply_roster_change(synapse, suggestion) do
    cond do
      String.contains?(suggestion, "who") -> apply_roster_who_change(synapse, suggestion)
      String.contains?(suggestion, "how") -> apply_roster_how_change(synapse, suggestion)
      true -> {:skip, "Could not interpret roster change: #{suggestion}"}
    end
  end

  defp apply_roster_who_change(synapse, suggestion) do
    case Regex.run(~r/to\s+['"]?(\w+)['"]?/i, suggestion) do
      [_, new_who] ->
        updated_roster = Enum.map(synapse.roster, fn step -> Map.put(step, "who", new_who) end)
        Ruminations.update_synapse(synapse, %{roster: updated_roster})

      _ ->
        {:skip, "Could not parse roster 'who' change from: #{suggestion}"}
    end
  end

  defp apply_roster_how_change(synapse, suggestion) do
    case Regex.run(~r/to\s+['"]?(\w+)['"]?/i, suggestion) do
      [_, new_how] when new_how in ~w(consensus solo majority) ->
        updated_roster = Enum.map(synapse.roster, fn step -> Map.put(step, "how", new_how) end)
        Ruminations.update_synapse(synapse, %{roster: updated_roster})

      _ ->
        {:skip, "Could not parse roster 'how' change from: #{suggestion}"}
    end
  end

  # Schedule changes: update the synapse's trigger schedule
  defp apply_schedule_change(synapse, suggestion) do
    case Regex.run(~r/(\d+\s+[\d*\/]+\s+[\d*\/]+\s+[\d*\/]+\s+[\d*\/]+)/, suggestion) do
      [_, cron] ->
        Ruminations.update_synapse(synapse, %{schedule: cron})

      _ ->
        {:skip, "Could not parse cron schedule from: #{suggestion}"}
    end
  end

  # Prompt changes are too open-ended to auto-apply safely
  defp apply_prompt_change(_synapse, _suggestion) do
    {:skip, "Prompt changes require manual review — see proposal details for suggested wording"}
  end
end
