defmodule ExCaliburUI.Components.CharterPicker do
  @moduledoc """
  Charter picker component.
  Displays a grid of available pipeline charters with preview
  and one-click installation.
  """
  use Phoenix.Component

  import SaladUI.Badge
  import SaladUI.Button
  import SaladUI.Card

  attr :charters, :list, required: true
  attr :on_install, :any, required: true
  attr :on_preview, :any, default: nil
  attr :class, :string, default: nil

  @doc """
  Renders charter picker grid.

  Each charter should have:
  - `:name` — display name
  - `:description` — short description
  - `:roles` — list of role names
  - `:actions` — list of action names
  - `:strategy` — consensus strategy name
  """
  def charter_picker(assigns) do
    ~H"""
    <div class={["grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4", @class]}>
      <.charter_card
        :for={charter <- @charters}
        charter={charter}
        on_install={@on_install}
        on_preview={@on_preview}
      />
    </div>
    """
  end

  defp charter_card(assigns) do
    ~H"""
    <.card class="flex flex-col">
      <.card_header>
        <.card_title class="text-lg">{@charter.name}</.card_title>
        <.card_description>{@charter.description}</.card_description>
      </.card_header>
      <.card_content class="flex-1">
        <div class="space-y-2">
          <div>
            <span class="text-xs text-muted-foreground">Roles:</span>
            <div class="flex flex-wrap gap-1 mt-1">
              <.badge :for={role <- @charter.roles} variant="secondary">{role}</.badge>
            </div>
          </div>
          <div>
            <span class="text-xs text-muted-foreground">Actions:</span>
            <div class="flex flex-wrap gap-1 mt-1">
              <.badge :for={action <- @charter.actions} variant="outline">{action}</.badge>
            </div>
          </div>
          <div>
            <span class="text-xs text-muted-foreground">Strategy:</span>
            <.badge>{@charter.strategy}</.badge>
          </div>
        </div>
      </.card_content>
      <div class="p-6 pt-0 flex gap-2">
        <.button phx-click={@on_install} phx-value-charter={@charter.name} size="sm">
          Install
        </.button>
        <.button
          :if={@on_preview}
          phx-click={@on_preview}
          phx-value-charter={@charter.name}
          variant="outline"
          size="sm"
        >
          Preview
        </.button>
      </div>
    </.card>
    """
  end
end
