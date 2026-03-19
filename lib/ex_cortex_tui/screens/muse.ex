defmodule ExCortexTUI.Screens.Muse do
  @moduledoc "Muse screen -- data-grounded chat (RAG)."

  @behaviour ExCortexTUI.Screen

  alias ExCortexTUI.Screens.Chat

  @impl true
  def init(_), do: Chat.init(mode: :muse, title: "Muse \u2014 data-grounded chat")

  @impl true
  def render(state), do: Chat.render(state)

  @impl true
  def handle_key(key, state), do: Chat.handle_key(key, state)

  @impl true
  def handle_info(msg, state), do: Chat.handle_info(msg, state)
end
