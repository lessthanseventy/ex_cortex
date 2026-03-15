defmodule ExCortex.Library do
  @moduledoc false
  import Ecto.Query

  alias ExCortex.Library.Dictionary
  alias ExCortex.Repo

  def list_dictionaries, do: Repo.all(from(d in Dictionary, order_by: d.name))
  def get_dictionary!(id), do: Repo.get!(Dictionary, id)
  def get_dictionary(id), do: Repo.get(Dictionary, id)
  def get_dictionary_by_name(name), do: Repo.get_by(Dictionary, name: name)
  def create_dictionary(attrs), do: %Dictionary{} |> Dictionary.changeset(attrs) |> Repo.insert()
  def update_dictionary(%Dictionary{} = d, attrs), do: d |> Dictionary.changeset(attrs) |> Repo.update()
  def delete_dictionary(%Dictionary{} = d), do: Repo.delete(d)
end
