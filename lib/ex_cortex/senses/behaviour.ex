defmodule ExCortex.Senses.Behaviour do
  @moduledoc false
  alias ExCortex.Senses.Item

  @callback init(config :: map()) :: {:ok, state :: map()} | {:error, term()}
  @callback fetch(state :: map(), config :: map()) :: {:ok, [Item.t()], map()} | {:error, term()}
  @callback stop(state :: map()) :: :ok

  @optional_callbacks [stop: 1]
end
