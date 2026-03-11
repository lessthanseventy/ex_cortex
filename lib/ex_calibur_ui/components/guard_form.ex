defmodule ExCaliburUI.Components.GuardForm do
  @moduledoc """
  LiveView form for configuring Excellence guards.
  Supports guard type selection and custom check logic description.
  """
  use Phoenix.Component

  import SaladUI.Button
  import SaladUI.Card
  import SaladUI.Input
  import SaladUI.Textarea

  attr :guard, :map, default: %{name: "", type: "pass", description: ""}
  attr :on_save, :any, required: true
  attr :class, :string, default: nil

  def guard_form(assigns) do
    ~H"""
    <.card class={@class}>
      <.card_header>
        <.card_title>Guard Configuration</.card_title>
        <.card_description>Post-consensus hard constraints</.card_description>
      </.card_header>
      <.card_content>
        <form phx-submit={@on_save} class="space-y-4">
          <div>
            <label class="text-sm font-medium">Name</label>
            <.input type="text" name="guard[name]" value={@guard[:name]} placeholder="rate-limiter" />
          </div>

          <div>
            <label class="text-sm font-medium">Type</label>
            <div class="flex gap-2 mt-1">
              <.type_option current={@guard[:type]} value="pass" label="Pass" />
              <.type_option current={@guard[:type]} value="block" label="Block" />
              <.type_option current={@guard[:type]} value="modify" label="Modify" />
            </div>
          </div>

          <div>
            <label class="text-sm font-medium">Description</label>
            <.textarea
              name="guard[description]"
              value={@guard[:description]}
              placeholder="Describe what this guard checks..."
              rows={3}
            />
          </div>

          <div class="pt-2">
            <.button type="submit">Save Guard</.button>
          </div>
        </form>
      </.card_content>
    </.card>
    """
  end

  defp type_option(assigns) do
    selected = to_string(assigns.current) == to_string(assigns.value)
    assigns = assign(assigns, :selected, selected)

    ~H"""
    <label class={"cursor-pointer px-3 py-1.5 rounded border text-sm #{if @selected, do: "bg-primary text-primary-foreground", else: "bg-background"}"}>
      <input type="radio" name="guard[type]" value={@value} checked={@selected} class="sr-only" />
      {@label}
    </label>
    """
  end
end
