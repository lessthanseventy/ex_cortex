defmodule ExCortex.Lexicon do
  @moduledoc false
  import Ecto.Query

  alias ExCortex.Lexicon.Axiom
  alias ExCortex.Repo

  def list_axioms, do: Repo.all(from(a in Axiom, order_by: a.name))
  def get_axiom!(id), do: Repo.get!(Axiom, id)
  def get_axiom(id), do: Repo.get(Axiom, id)
  def get_axiom_by_name(name), do: Repo.get_by(Axiom, name: name)
  def create_axiom(attrs), do: %Axiom{} |> Axiom.changeset(attrs) |> Repo.insert()
  def update_axiom(%Axiom{} = a, attrs), do: a |> Axiom.changeset(attrs) |> Repo.update()
  def delete_axiom(%Axiom{} = a), do: Repo.delete(a)
end
