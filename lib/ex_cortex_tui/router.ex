defmodule ExCortexTUI.Router do
  @moduledoc "Maps keyboard input to screen switches or forwards to active screen."

  @nav_keys %{
    "c" => :cortex,
    "d" => :daydreams,
    "p" => :proposals,
    "w" => :wonder,
    "m" => :muse,
    "h" => :hud,
    "l" => :logs,
    "?" => :help
  }

  @chat_screens [:wonder, :muse]

  def handle_key(_key, current_screen) when current_screen in @chat_screens do
    :forward
  end

  def handle_key(key, _current_screen) do
    case Map.get(@nav_keys, key) do
      nil -> :forward
      screen -> {:switch, screen}
    end
  end
end
