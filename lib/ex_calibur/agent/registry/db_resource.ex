defmodule ExCalibur.Agent.Registry.DBResource do
  @moduledoc "Wraps a Member DB row as a registry resource."

  alias ExCalibur.Schemas.Member

  defstruct [:type, :name, :definition, :status, :source, :config]

  def wrap(%Member{} = rd) do
    %__MODULE__{
      type: String.to_atom(rd.type),
      name: rd.name,
      definition: rd,
      status: String.to_atom(rd.status),
      source: :db,
      config: rd.config
    }
  end
end
