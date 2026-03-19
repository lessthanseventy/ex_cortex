defmodule ExCortexTUI.Screens.Wonder do
  @moduledoc "Wonder screen -- pure LLM chat, no data grounding."

  @behaviour ExCortexTUI.Screen

  alias ExCortexTUI.Screens.Chat

  @impl true
  def init(_), do: Chat.init(mode: :wonder, title: "Wonder \u2014 pure LLM chat")

  @impl true
  def render(state), do: Chat.render(state)

  @impl true
  def handle_key(key, state), do: Chat.handle_key(key, state)

  @impl true
  def handle_info(msg, state), do: Chat.handle_info(msg, state)
end
