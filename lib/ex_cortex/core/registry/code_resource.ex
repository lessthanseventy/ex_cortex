defmodule ExCortex.Core.Registry.CodeResource do
  @moduledoc "Wraps a compiled module as a registry resource."

  defstruct [:type, :name, :module, :status, :source]

  def wrap(type, module) do
    %__MODULE__{
      type: type,
      name: module |> Module.split() |> List.last() |> Macro.underscore(),
      module: module,
      status: :active,
      source: :code
    }
  end
end
