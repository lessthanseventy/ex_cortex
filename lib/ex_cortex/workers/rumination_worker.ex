defmodule ExCortex.Workers.RuminationWorker do
  @moduledoc false
  use Oban.Worker, queue: :default

  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Runner

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"rumination_id" => rumination_id}}) do
    rumination = Ruminations.get_rumination!(rumination_id)
    {:ok, _} = Runner.run(rumination, "")
    # Mark as done after firing
    Ruminations.update_rumination(rumination, %{status: "done"})
    :ok
  end
end
