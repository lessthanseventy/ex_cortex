defmodule ExCalibur.Sources.Behaviour do
  @moduledoc false
  alias ExCalibur.Sources.SourceItem

  @callback init(config :: map()) :: {:ok, state :: map()} | {:error, term()}
  @callback fetch(state :: map(), config :: map()) :: {:ok, [SourceItem.t()], map()} | {:error, term()}
  @callback stop(state :: map()) :: :ok

  @optional_callbacks [stop: 1]
end
