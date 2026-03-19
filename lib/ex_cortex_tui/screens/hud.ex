defmodule ExCortexTUI.Screens.HUD do
  @moduledoc "HUD screen: machine-readable dashboard view using the shared HUD formatter."

  @behaviour ExCortexTUI.Screen

  @impl true
  def init(_), do: %{data: ExCortexTUI.HUD.gather_state()}

  @impl true
  def render(state), do: ExCortexTUI.HUD.Formatter.format(state.data)

  @impl true
  def handle_key(_key, state), do: {:noreply, state}

  @impl true
  def handle_info(_msg, state), do: {:noreply, %{state | data: ExCortexTUI.HUD.gather_state()}}
end
