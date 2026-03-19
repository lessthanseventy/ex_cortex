defmodule ExCortex.Ruminations.ProposalPolicy do
  @moduledoc """
  Evaluates proposals against auto-approval policies.

  Policies are stored in Settings (Instinct UI) as a list of rule maps:

      [
        %{
          "type" => "tool_action",
          "tool_name" => "create_github_issue",
          "min_trust" => 0.85,
          "action" => "auto_approve"
        },
        %{
          "type" => "roster_change",
          "max_age_hours" => 48,
          "action" => "auto_reject"
        }
      ]

  Each rule has a "type" matcher and optional conditions. The first matching rule wins.
  If no rule matches, the proposal stays "pending" (default behavior).
  """

  alias ExCortex.Settings

  require Logger

  @doc """
  Evaluate a proposal against configured policies.
  Returns :pending (no matching rule), :auto_approve, or :auto_reject.
  """
  def evaluate(proposal) do
    policies = load_policies()

    Enum.find_value(policies, :pending, fn rule ->
      if matches?(rule, proposal), do: action_for(rule)
    end)
  end

  @doc """
  Check and auto-apply pending proposals that have exceeded time thresholds.
  Called periodically (e.g., from a scheduled job or the Analyst Sweep).
  """
  def sweep_stale_proposals do
    import Ecto.Query

    alias ExCortex.Ruminations
    alias ExCortex.Ruminations.Proposal

    policies = load_policies()
    stale_rules = Enum.filter(policies, &Map.has_key?(&1, "max_age_hours"))

    if stale_rules != [] do
      pending =
        ExCortex.Repo.all(
          from p in Proposal,
            where: p.status == "pending",
            preload: [:synapse]
        )

      Enum.each(pending, fn proposal ->
        age_hours = DateTime.diff(DateTime.utc_now(), proposal.inserted_at, :hour)

        matching_rule =
          Enum.find(stale_rules, fn rule ->
            matches?(rule, proposal) && age_hours >= (rule["max_age_hours"] || 999_999)
          end)

        if matching_rule do
          action = action_for(matching_rule)
          Logger.info("[ProposalPolicy] Stale proposal #{proposal.id}: #{action} (age: #{age_hours}h)")

          case action do
            :auto_approve -> Ruminations.approve_proposal(proposal)
            :auto_reject -> Ruminations.reject_proposal(proposal)
            _ -> :ok
          end
        end
      end)
    end
  end

  defp load_policies do
    case Settings.get(:proposal_policies) do
      policies when is_list(policies) -> policies
      _ -> []
    end
  end

  defp matches?(rule, proposal) do
    type_matches?(rule, proposal) &&
      tool_matches?(rule, proposal) &&
      trust_matches?(rule, proposal)
  end

  defp type_matches?(%{"type" => type}, %{type: ptype}), do: type == ptype
  defp type_matches?(%{"type" => type}, %{"type" => ptype}), do: type == ptype
  defp type_matches?(_, _), do: true

  defp tool_matches?(%{"tool_name" => name}, %{tool_name: tname}), do: name == tname
  defp tool_matches?(%{"tool_name" => name}, %{"tool_name" => tname}), do: name == tname
  defp tool_matches?(_, _), do: true

  defp trust_matches?(%{"min_trust" => min_trust}, proposal) do
    # Get the neuron that generated this proposal (from the synapse's last run)
    # For now, use a simple heuristic: check if all neurons on the synapse have high trust
    synapse_id = proposal.synapse_id || Map.get(proposal, :synapse_id)

    if synapse_id do
      scores = ExCortex.TrustScorer.list_scores()
      avg = if scores == [], do: 1.0, else: Enum.sum(Enum.map(scores, & &1.score)) / length(scores)
      avg >= min_trust
    else
      true
    end
  end

  defp trust_matches?(_, _), do: true

  defp action_for(%{"action" => "auto_approve"}), do: :auto_approve
  defp action_for(%{"action" => "auto_reject"}), do: :auto_reject
  defp action_for(_), do: :pending
end
