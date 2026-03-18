defmodule ExCortex.Ruminations do
  @moduledoc false
  import Ecto.Query

  alias ExCortex.Repo
  alias ExCortex.Ruminations.Daydream
  alias ExCortex.Ruminations.Impulse
  alias ExCortex.Ruminations.Proposal
  alias ExCortex.Ruminations.Rumination
  alias ExCortex.Ruminations.Synapse

  # --- Synapses (step definitions within a rumination) ---

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

  # --- Ruminations (pipeline definitions) ---

  def list_ruminations_for_source(source_id) do
    Repo.all(
      from t in Rumination,
        where:
          t.trigger == "source" and
            t.status == "active" and
            fragment("? = ANY(?)", ^source_id, t.source_ids)
    )
  end

  def list_ruminations do
    Repo.all(from t in Rumination, order_by: [asc: t.name])
  end

  def get_rumination!(id), do: Repo.get!(Rumination, id)

  def create_rumination(attrs) do
    case %Rumination{} |> Rumination.changeset(attrs) |> Repo.insert() do
      {:ok, rumination} = result ->
        maybe_schedule_once_job(rumination)
        result

      error ->
        error
    end
  end

  def update_rumination(%Rumination{} = rumination, attrs) do
    case rumination |> Rumination.changeset(attrs) |> Repo.update() do
      {:ok, updated} = result ->
        maybe_schedule_once_job(updated)
        result

      error ->
        error
    end
  end

  def delete_rumination(%Rumination{} = rumination), do: Repo.delete(rumination)

  defp maybe_schedule_once_job(%Rumination{trigger: "once", run_at: run_at, id: id}) when not is_nil(run_at) do
    %{rumination_id: id}
    |> ExCortex.Workers.RuminationWorker.new(scheduled_at: run_at)
    |> Oban.insert()
  end

  defp maybe_schedule_once_job(_rumination), do: :ok

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

  # --- Daydreams (rumination executions) ---

  def list_daydreams(%Rumination{id: rumination_id}) do
    Repo.all(
      from r in Daydream,
        where: r.rumination_id == ^rumination_id,
        order_by: [desc: r.inserted_at],
        limit: 10
    )
  end

  def latest_daydream(rumination_id) do
    Repo.one(
      from d in Daydream,
        where: d.rumination_id == ^rumination_id,
        order_by: [desc: d.inserted_at, desc: d.id],
        limit: 1
    )
  end

  def running_daydream_by_fingerprint(fingerprint) do
    Repo.one(
      from d in Daydream,
        where: d.fingerprint == ^fingerprint and d.status == "running",
        limit: 1
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
