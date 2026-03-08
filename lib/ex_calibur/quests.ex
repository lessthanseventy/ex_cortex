defmodule ExCalibur.Quests do
  @moduledoc false
  import Ecto.Query

  alias ExCalibur.Quests.Campaign
  alias ExCalibur.Quests.CampaignRun
  alias ExCalibur.Quests.Proposal
  alias ExCalibur.Quests.Quest
  alias ExCalibur.Quests.QuestRun
  alias ExCalibur.Repo

  # --- Quests ---

  def list_quests do
    Repo.all(from q in Quest, order_by: [asc: q.name])
  end

  def get_quest!(id), do: Repo.get!(Quest, id)

  def create_quest(attrs) do
    %Quest{} |> Quest.changeset(attrs) |> Repo.insert()
  end

  def update_quest(%Quest{} = quest, attrs) do
    quest |> Quest.changeset(attrs) |> Repo.update()
  end

  def delete_quest(%Quest{} = quest), do: Repo.delete(quest)

  # --- Campaigns ---

  def list_campaigns do
    Repo.all(from c in Campaign, order_by: [asc: c.name])
  end

  def get_campaign!(id), do: Repo.get!(Campaign, id)

  def create_campaign(attrs) do
    %Campaign{} |> Campaign.changeset(attrs) |> Repo.insert()
  end

  def update_campaign(%Campaign{} = campaign, attrs) do
    campaign |> Campaign.changeset(attrs) |> Repo.update()
  end

  def delete_campaign(%Campaign{} = campaign), do: Repo.delete(campaign)

  # --- Quest Runs ---

  def list_quest_runs(%Quest{id: quest_id}) do
    Repo.all(
      from r in QuestRun,
        where: r.quest_id == ^quest_id,
        order_by: [desc: r.inserted_at],
        limit: 10
    )
  end

  def create_quest_run(attrs) do
    %QuestRun{} |> QuestRun.changeset(attrs) |> Repo.insert()
  end

  def update_quest_run(%QuestRun{} = run, attrs) do
    run |> QuestRun.changeset(attrs) |> Repo.update()
  end

  # --- Campaign Runs ---

  def list_campaign_runs(%Campaign{id: campaign_id}) do
    Repo.all(
      from r in CampaignRun,
        where: r.campaign_id == ^campaign_id,
        order_by: [desc: r.inserted_at],
        limit: 10
    )
  end

  def create_campaign_run(attrs) do
    %CampaignRun{} |> CampaignRun.changeset(attrs) |> Repo.insert()
  end

  def update_campaign_run(%CampaignRun{} = run, attrs) do
    run |> CampaignRun.changeset(attrs) |> Repo.update()
  end

  # --- Proposals ---

  def list_proposals(opts \\ []) do
    query = from p in Proposal, order_by: [desc: p.inserted_at], preload: [:quest]

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> from p in query, where: p.status == ^status
      end

    Repo.all(query)
  end

  def create_proposal(attrs) do
    %Proposal{} |> Proposal.changeset(attrs) |> Repo.insert()
  end

  def update_proposal(%Proposal{} = proposal, attrs) do
    proposal |> Proposal.changeset(attrs) |> Repo.update()
  end

  def approve_proposal(%Proposal{} = proposal) do
    proposal
    |> Proposal.changeset(%{status: "approved", applied_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def reject_proposal(%Proposal{} = proposal) do
    proposal |> Proposal.changeset(%{status: "rejected"}) |> Repo.update()
  end
end
