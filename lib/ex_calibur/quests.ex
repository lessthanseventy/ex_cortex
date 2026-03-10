defmodule ExCalibur.Quests do
  @moduledoc false
  import Ecto.Query

  alias ExCalibur.Quests.Proposal
  alias ExCalibur.Quests.Quest
  alias ExCalibur.Quests.QuestRun
  alias ExCalibur.Quests.Step
  alias ExCalibur.Quests.StepRun
  alias ExCalibur.Repo

  # --- Steps (formerly Quests) ---

  def list_steps do
    Repo.all(from s in Step, order_by: [asc: s.name])
  end

  def list_steps_for_source(source_id) do
    Repo.all(
      from s in Step,
        where:
          s.trigger == "source" and
            s.status == "active" and
            fragment("? = ANY(?)", ^source_id, s.source_ids)
    )
  end

  def get_step!(id), do: Repo.get!(Step, id)

  def create_step(attrs) do
    %Step{} |> Step.changeset(attrs) |> Repo.insert()
  end

  def update_step(%Step{} = step, attrs) do
    step |> Step.changeset(attrs) |> Repo.update()
  end

  def delete_step(%Step{} = step), do: Repo.delete(step)

  # --- Quests (formerly Campaigns) ---

  def list_quests_for_source(source_id) do
    Repo.all(
      from q in Quest,
        where:
          q.trigger == "source" and
            q.status == "active" and
            fragment("? = ANY(?)", ^source_id, q.source_ids)
    )
  end

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

  # --- Step Runs (formerly QuestRuns) ---

  def list_step_runs(%Step{id: step_id}) do
    Repo.all(
      from r in StepRun,
        where: r.step_id == ^step_id,
        order_by: [desc: r.inserted_at],
        limit: 10
    )
  end

  def create_step_run(attrs) do
    %StepRun{} |> StepRun.changeset(attrs) |> Repo.insert()
  end

  def update_step_run(%StepRun{} = run, attrs) do
    run |> StepRun.changeset(attrs) |> Repo.update()
  end

  # --- Quest Runs (formerly CampaignRuns) ---

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

  # --- Proposals ---

  def list_proposals(opts \\ []) do
    query = from p in Proposal, order_by: [desc: p.inserted_at], preload: [:step]

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
