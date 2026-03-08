defmodule ExCellenceServer.Quests do
  @moduledoc false
  import Ecto.Query

  alias ExCellenceServer.Quests.Campaign
  alias ExCellenceServer.Quests.CampaignRun
  alias ExCellenceServer.Quests.Quest
  alias ExCellenceServer.Quests.QuestRun
  alias ExCellenceServer.Repo

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
end
