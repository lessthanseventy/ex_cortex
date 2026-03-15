defmodule ExCortexTUI.Router do
  @moduledoc "Routes keyboard input and renders the active screen."

  alias ExCortexTUI.Screens

  @screen_keys %{
    "c" => :cortex,
    "n" => :neurons,
    "t" => :thoughts,
    "m" => :memory,
    "s" => :senses,
    "i" => :instinct,
    "g" => :guide
  }

  def handle_key(%{key: key}, _current_screen) when is_map_key(@screen_keys, key) do
    {:switch, Map.fetch!(@screen_keys, key)}
  end

  def handle_key(_, _), do: :ignore

  def render(:cortex, state), do: Screens.Cortex.render(state)
  def render(:neurons, state), do: Screens.Neurons.render(state)
  def render(:thoughts, state), do: Screens.Thoughts.render(state)
  def render(:memory, state), do: Screens.Memory.render(state)
  def render(:senses, state), do: Screens.Senses.render(state)
  def render(:instinct, state), do: Screens.Instinct.render(state)
  def render(:guide, state), do: Screens.Guide.render(state)
end
