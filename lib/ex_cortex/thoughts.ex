defmodule ExCortex.Thoughts do
  @moduledoc "Context for single-step thoughts — wonderings, musings, and saved queries."

  import Ecto.Query

  alias ExCortex.Repo
  alias ExCortex.Thoughts.Thought

  def list_thoughts(opts \\ []) do
    query = from(t in Thought, order_by: [desc: t.inserted_at])

    query =
      case Keyword.get(opts, :scope) do
        nil -> query
        scope -> where(query, [t], t.scope == ^scope)
      end

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [t], t.status == ^status)
      end

    Repo.all(query)
  end

  def get_thought!(id), do: Repo.get!(Thought, id)

  def create_thought(attrs) do
    case %Thought{} |> Thought.changeset(attrs) |> Repo.insert() do
      {:ok, thought} = result ->
        Phoenix.PubSub.broadcast(ExCortex.PubSub, "thoughts", {:thought_created, thought})
        result

      error ->
        error
    end
  end

  def update_thought(%Thought{} = t, attrs) do
    t
    |> Thought.changeset(attrs)
    |> Repo.update()
  end

  def delete_thought(%Thought{} = t), do: Repo.delete(t)

  def save_to_memory(%Thought{question: q, answer: a, tags: tags} = thought) do
    with {:ok, engram} <-
           ExCortex.Memory.create_engram(%{
             title: q,
             body: a,
             tags: tags || [],
             source: "muse",
             category: "episodic"
           }),
         {:ok, _thought} <- update_thought(thought, %{status: "saved"}) do
      {:ok, engram}
    end
  end
end
