defmodule ExCortexTUI.Screens.Help do
  @moduledoc "Help screen: keyboard shortcuts and navigation reference."

  @behaviour ExCortexTUI.Screen

  @impl true
  def init(_), do: %{}

  @impl true
  def render(_state) do
    [
      Owl.Data.tag("Keyboard Shortcuts", :yellow),
      "\n\n",
      help_section("Navigation", [
        {"c", "Cortex dashboard"},
        {"d", "Daydreams — list and tail"},
        {"p", "Proposals — review and approve"},
        {"w", "Wonder — pure LLM chat"},
        {"m", "Muse — data-grounded chat"},
        {"h", "HUD — machine-readable view"},
        {"?", "This help screen"},
        {"q", "Quit"}
      ]),
      "\n",
      help_section("In Lists", [
        {"j/k", "Move cursor down/up"},
        {"Enter", "Select / expand"},
        {"Esc", "Back to previous view"}
      ]),
      "\n",
      help_section("In Chat", [
        {"Enter", "Send message"},
        {"Ctrl+C", "Cancel streaming response"},
        {"Esc", "Back to navigation"}
      ]),
      "\n",
      help_section("In Proposals", [
        {"y", "Approve selected proposal"},
        {"n", "Reject selected proposal"},
        {"s", "Skip to next"}
      ])
    ]
  end

  @impl true
  def handle_key(_, state), do: {:noreply, state}

  defp help_section(title, items) do
    header = Owl.Data.tag(title, :bright)

    rows =
      Enum.map(items, fn {key, desc} ->
        ["\n  ", Owl.Data.tag(String.pad_trailing(key, 12), :cyan), desc]
      end)

    [header | rows]
  end
end
