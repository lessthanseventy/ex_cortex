import Ecto.Query
alias ExCalibur.Repo
alias ExCalibur.Quests.Quest

quests = Repo.all(from q in Quest)

Enum.each(quests, fn q ->
  clean = Enum.reject(q.steps, fn s -> is_nil(s["step_id"]) end)
  removed = length(q.steps) - length(clean)

  if removed > 0 do
    IO.puts("Quest #{q.id} \"#{q.name}\": removing #{removed} nil step(s)")
    q |> Quest.changeset(%{steps: clean}) |> Repo.update!()
  end
end)

IO.puts("Done.")
