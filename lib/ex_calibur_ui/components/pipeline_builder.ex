defmodule ExCaliburUI.Components.PipelineBuilder do
  @moduledoc """
  LiveView component for visual pipeline construction.
  Allows selecting middleware, configuring options, and ordering
  the pipeline stages via drag-and-drop reorder.
  """
  use Phoenix.Component

  import SaladUI.Button
  import SaladUI.Card

  @available_middleware []

  attr :pipeline, :list, default: []
  attr :on_save, :any, required: true
  attr :class, :string, default: nil

  def pipeline_builder(assigns) do
    assigns = assign(assigns, :available, @available_middleware)

    ~H"""
    <.card class={@class}>
      <.card_header>
        <.card_title>Pipeline Builder</.card_title>
        <.card_description>Configure middleware execution order</.card_description>
      </.card_header>
      <.card_content>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <h4 class="text-sm font-medium mb-2">Available Middleware</h4>
            <div class="space-y-1">
              <div
                :for={mw <- @available}
                class="p-2 border rounded cursor-pointer hover:bg-accent text-sm"
                phx-click="add_middleware"
                phx-value-module={mw.module}
              >
                <span class="font-medium">{mw.name}</span>
                <span class="text-muted-foreground ml-1">— {mw.description}</span>
              </div>
            </div>
          </div>

          <div>
            <h4 class="text-sm font-medium mb-2">Pipeline ({length(@pipeline)} stages)</h4>
            <div
              id="pipeline-stages"
              phx-hook="Sortable"
              class="space-y-1 min-h-[100px] border rounded p-2"
            >
              <.pipeline_stage
                :for={{stage, i} <- Enum.with_index(@pipeline)}
                stage={stage}
                index={i}
              />
              <p :if={@pipeline == []} class="text-sm text-muted-foreground p-4 text-center">
                Click middleware to add stages
              </p>
            </div>
          </div>
        </div>

        <div class="flex gap-2 pt-4">
          <.button phx-click={@on_save}>Save Pipeline</.button>
        </div>
      </.card_content>
    </.card>
    """
  end

  defp pipeline_stage(assigns) do
    name = assigns.stage[:name] || assigns.stage["name"] || assigns.stage[:module] || "Unknown"

    assigns = assign(assigns, :display_name, name)

    ~H"""
    <div
      class="flex items-center justify-between p-2 border rounded bg-background"
      data-index={@index}
    >
      <span class="text-sm font-mono">{@index + 1}. {@display_name}</span>
      <.button
        type="button"
        variant="ghost"
        size="sm"
        phx-click="remove_middleware"
        phx-value-index={@index}
      >
        ✕
      </.button>
    </div>
    """
  end
end
