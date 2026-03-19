defmodule ExCortexTUI.Screen do
  @moduledoc "Behaviour for TUI screens."

  @callback init(map()) :: map()
  @callback render(map()) :: Owl.Data.t()
  @callback handle_key(binary(), map()) :: {:noreply, map()} | {:switch, atom()} | {:quit, map()}
  @callback handle_info(term(), map()) :: {:noreply, map()}

  @optional_callbacks [handle_info: 2]
end
