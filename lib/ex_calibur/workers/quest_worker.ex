defmodule ExCalibur.Workers.QuestWorker do
  @moduledoc false
  use Oban.Worker, queue: :default

  alias ExCalibur.QuestRunner
  alias ExCalibur.Quests

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"quest_id" => quest_id}}) do
    quest = Quests.get_quest!(quest_id)
    {:ok, _} = QuestRunner.run(quest, "")
    # Mark as done after firing
    Quests.update_quest(quest, %{status: "done"})
    :ok
  end
end
