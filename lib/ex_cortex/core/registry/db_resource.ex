defmodule ExCortex.Core.Registry.DBResource do
  @moduledoc "Wraps a Neuron DB row as a registry resource."

  alias ExCortex.Neurons.Neuron

  defstruct [:type, :name, :definition, :status, :source, :config]

  def wrap(%Neuron{} = rd) do
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
