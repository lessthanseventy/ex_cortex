defmodule ExCaliburUI.Components.RoleForm do
  @moduledoc """
  LiveView form component for creating/editing Excellence roles.
  Supports name, system prompt, perspectives management, model selection,
  and parse strategy configuration.
  """
  use Phoenix.Component

  import SaladUI.Button
  import SaladUI.Card
  import SaladUI.Input
  import SaladUI.Textarea

  attr :role, :map, default: %{name: "", system_prompt: "", perspectives: [], parse_strategy: "default"}
  attr :on_save, :any, required: true
  attr :on_cancel, :any, default: nil
  attr :class, :string, default: nil

  def role_form(assigns) do
    ~H"""
    <.card class={@class}>
      <.card_header>
        <.card_title>{if @role[:name] != "", do: "Edit Role", else: "New Role"}</.card_title>
      </.card_header>
      <.card_content>
        <form phx-submit={@on_save} class="space-y-4">
          <div>
            <label class="text-sm font-medium">Name</label>
            <.input type="text" name="role[name]" value={@role[:name]} placeholder="safety-reviewer" />
          </div>

          <div>
            <label class="text-sm font-medium">System Prompt</label>
            <.textarea
              name="role[system_prompt]"
              value={@role[:system_prompt]}
              placeholder="You are a..."
              rows={4}
            />
          </div>

          <div>
            <label class="text-sm font-medium">Perspectives</label>
            <div class="space-y-2 mt-1">
              <.perspective_row
                :for={{p, i} <- Enum.with_index(@role[:perspectives] || [])}
                perspective={p}
                index={i}
              />
              <.button type="button" variant="outline" size="sm" phx-click="add_perspective">
                + Add Perspective
              </.button>
            </div>
          </div>

          <div>
            <label class="text-sm font-medium">Parse Strategy</label>
            <.input
              type="text"
              name="role[parse_strategy]"
              value={@role[:parse_strategy] || "default"}
            />
          </div>

          <div class="flex gap-2 pt-2">
            <.button type="submit">Save Role</.button>
            <.button :if={@on_cancel} type="button" variant="outline" phx-click={@on_cancel}>
              Cancel
            </.button>
          </div>
        </form>
      </.card_content>
    </.card>
    """
  end

  defp perspective_row(assigns) do
    ~H"""
    <div class="flex gap-2 items-center p-2 border rounded">
      <.input
        type="text"
        name={"role[perspectives][#{@index}][name]"}
        value={@perspective[:name] || @perspective["name"]}
        placeholder="alpha"
        class="w-24"
      />
      <.input
        type="text"
        name={"role[perspectives][#{@index}][model]"}
        value={@perspective[:model] || @perspective["model"]}
        placeholder="gemma3:4b"
        class="flex-1"
      />
      <.input
        type="text"
        name={"role[perspectives][#{@index}][strategy]"}
        value={@perspective[:strategy] || @perspective["strategy"]}
        placeholder="cod"
        class="w-20"
      />
      <.button
        type="button"
        variant="ghost"
        size="sm"
        phx-click="remove_perspective"
        phx-value-index={@index}
      >
        ✕
      </.button>
    </div>
    """
  end
end
