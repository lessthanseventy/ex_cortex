defmodule ExCortex.Thoughts do
  @moduledoc false
  import Ecto.Query

  alias ExCortex.Repo
  alias ExCortex.Thoughts.Daydream
  alias ExCortex.Thoughts.Impulse
  alias ExCortex.Thoughts.Proposal
  alias ExCortex.Thoughts.Synapse
  alias ExCortex.Thoughts.Thought

  # --- Synapses (step definitions within a thought) ---

  def list_synapses do
    Repo.all(from s in Synapse, order_by: [asc: s.name])
  end

  def list_synapses_for_source(source_id) do
    Repo.all(
      from s in Synapse,
        where:
          s.trigger == "source" and
            s.status == "active" and
            fragment("? = ANY(?)", ^source_id, s.source_ids)
    )
  end

  def get_synapse!(id), do: Repo.get!(Synapse, id)

  def create_synapse(attrs) do
    %Synapse{} |> Synapse.changeset(attrs) |> Repo.insert()
  end

  def update_synapse(%Synapse{} = synapse, attrs) do
    synapse |> Synapse.changeset(attrs) |> Repo.update()
  end

  def delete_synapse(%Synapse{} = synapse), do: Repo.delete(synapse)

  # --- Thoughts (pipeline definitions) ---

  def list_thoughts_for_source(source_id) do
    Repo.all(
      from t in Thought,
        where:
          t.trigger == "source" and
            t.status == "active" and
            fragment("? = ANY(?)", ^source_id, t.source_ids)
    )
  end

  def list_thoughts do
    Repo.all(from t in Thought, order_by: [asc: t.name])
  end

  def get_thought!(id), do: Repo.get!(Thought, id)

  def create_thought(attrs) do
    case %Thought{} |> Thought.changeset(attrs) |> Repo.insert() do
      {:ok, thought} = result ->
        maybe_schedule_once_job(thought)
        result

      error ->
        error
    end
  end

  def update_thought(%Thought{} = thought, attrs) do
    case thought |> Thought.changeset(attrs) |> Repo.update() do
      {:ok, updated} = result ->
        maybe_schedule_once_job(updated)
        result

      error ->
        error
    end
  end

  def delete_thought(%Thought{} = thought), do: Repo.delete(thought)

  defp maybe_schedule_once_job(%Thought{trigger: "once", run_at: run_at, id: id}) when not is_nil(run_at) do
    %{thought_id: id}
    |> ExCortex.Workers.QuestWorker.new(scheduled_at: run_at)
    |> Oban.insert()
  end

  defp maybe_schedule_once_job(_thought), do: :ok

  # --- Impulses (step executions within a daydream) ---

  def list_impulses(%Synapse{id: synapse_id}) do
    Repo.all(
      from r in Impulse,
        where: r.synapse_id == ^synapse_id,
        order_by: [desc: r.inserted_at],
        limit: 10
    )
  end

  def create_impulse(attrs) do
    %Impulse{} |> Impulse.changeset(attrs) |> Repo.insert()
  end

  def update_impulse(%Impulse{} = run, attrs) do
    run |> Impulse.changeset(attrs) |> Repo.update()
  end

  # --- Daydreams (thought executions) ---

  def list_daydreams(%Thought{id: thought_id}) do
    Repo.all(
      from r in Daydream,
        where: r.thought_id == ^thought_id,
        order_by: [desc: r.inserted_at],
        limit: 10
    )
  end

  def create_daydream(attrs) do
    %Daydream{} |> Daydream.changeset(attrs) |> Repo.insert()
  end

  def update_daydream(%Daydream{} = run, attrs) do
    run |> Daydream.changeset(attrs) |> Repo.update()
  end

  # --- Proposals ---

  def list_proposals(opts \\ []) do
    query = from p in Proposal, order_by: [desc: p.inserted_at], preload: [:synapse]

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

  def execute_tool_proposal(%Proposal{type: "tool_action", tool_name: tool_name, tool_args: tool_args} = proposal) do
    case ExCortex.Tools.Registry.get(tool_name) do
      nil ->
        update_proposal(proposal, %{status: "failed", result: "Tool #{tool_name} not found"})

      tool ->
        case tool.callback.(tool_args) do
          {:ok, result} ->
            update_proposal(proposal, %{status: "executed", result: to_string(result)})

          {:error, reason} ->
            update_proposal(proposal, %{status: "failed", result: inspect(reason)})
        end
    end
  end

  def execute_tool_proposal(_proposal), do: :noop
end
