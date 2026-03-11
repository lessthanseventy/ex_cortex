defmodule ExCaliburUI.Components.ActionsForm do
  @moduledoc """
  LiveView form for defining Excellence action sets.
  Supports adding/removing actions with conflict declarations.
  """
  use Phoenix.Component

  import SaladUI.Button
  import SaladUI.Card
  import SaladUI.Input

  attr :actions, :list, default: []
  attr :on_save, :any, required: true
  attr :class, :string, default: nil

  def actions_form(assigns) do
    ~H"""
    <.card class={@class}>
      <.card_header>
        <.card_title>Actions</.card_title>
        <.card_description>Define the decision space</.card_description>
      </.card_header>
      <.card_content>
        <form phx-submit={@on_save} class="space-y-4">
          <div class="space-y-2">
            <.action_row
              :for={{action, i} <- Enum.with_index(@actions)}
              action={action}
              index={i}
              all_actions={@actions}
            />
          </div>

          <.button type="button" variant="outline" size="sm" phx-click="add_action">
            + Add Action
          </.button>

          <div class="pt-2">
            <.button type="submit">Save Actions</.button>
          </div>
        </form>
      </.card_content>
    </.card>
    """
  end

  defp action_row(assigns) do
    name = assigns.action[:name] || assigns.action["name"] || ""

    assigns = assign(assigns, :action_name, name)

    ~H"""
    <div class="flex gap-2 items-center p-2 border rounded">
      <.input
        type="text"
        name={"actions[#{@index}][name]"}
        value={@action_name}
        placeholder="approve"
        class="w-32"
      />
      <span class="text-xs text-muted-foreground">conflicts:</span>
      <.input
        type="text"
        name={"actions[#{@index}][conflicts]"}
        value={format_conflicts(@action)}
        placeholder="reject,flag"
        class="flex-1"
      />
      <.button type="button" variant="ghost" size="sm" phx-click="remove_action" phx-value-index={@index}>
        ✕
      </.button>
    </div>
    """
  end

  defp format_conflicts(action) do
    conflicts = action[:conflicts_with] || action["conflicts_with"] || []
    Enum.join(conflicts, ",")
  end
end
