defmodule ExCortex.Workers.ThoughtWorker do
  @moduledoc false
  use Oban.Worker, queue: :default

  alias ExCortex.Thoughts
  alias ExCortex.Thoughts.Runner

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thought_id" => thought_id}}) do
    thought = Thoughts.get_thought!(thought_id)
    {:ok, _} = Runner.run(thought, "")
    # Mark as done after firing
    Thoughts.update_thought(thought, %{status: "done"})
    :ok
  end
end
