defmodule ExCaliburUI.Components.AIBuilder do
  @moduledoc """
  AI-assisted role builder component.
  Takes natural language description and generates role configuration
  including system prompt, perspectives, and parse config.
  """
  use Phoenix.Component

  import SaladUI.Button
  import SaladUI.Card
  import SaladUI.Textarea

  attr :description, :string, default: ""
  attr :generated, :map, default: nil
  attr :loading, :boolean, default: false
  attr :on_generate, :any, required: true
  attr :on_save, :any, required: true
  attr :class, :string, default: nil

  def ai_builder(assigns) do
    ~H"""
    <.card class={@class}>
      <.card_header>
        <.card_title>AI Role Builder</.card_title>
        <.card_description>
          Describe what you need and AI will generate the role configuration
        </.card_description>
      </.card_header>
      <.card_content class="space-y-4">
        <form phx-submit={@on_generate}>
          <.textarea
            name="description"
            value={@description}
            placeholder="I need a role that evaluates content safety for children..."
            rows={3}
          />
          <div class="mt-2">
            <.button type="submit" disabled={@loading}>
              {if @loading, do: "Generating...", else: "Generate Role"}
            </.button>
          </div>
        </form>

        <.generated_preview :if={@generated} generated={@generated} on_save={@on_save} />
      </.card_content>
    </.card>
    """
  end

  defp generated_preview(assigns) do
    ~H"""
    <div class="border rounded p-4 space-y-3 bg-muted/50">
      <h4 class="font-medium">Generated Configuration</h4>

      <div>
        <label class="text-xs text-muted-foreground">Name</label>
        <p class="font-mono text-sm">{@generated[:name]}</p>
      </div>

      <div>
        <label class="text-xs text-muted-foreground">System Prompt</label>
        <pre class="text-xs bg-background p-2 rounded mt-1 whitespace-pre-wrap">{@generated[:system_prompt]}</pre>
      </div>

      <div :if={@generated[:perspectives]}>
        <label class="text-xs text-muted-foreground">Perspectives</label>
        <div class="flex flex-wrap gap-1 mt-1">
          <span
            :for={p <- @generated[:perspectives]}
            class="px-2 py-0.5 bg-background border rounded text-xs"
          >
            {p[:name] || p}
          </span>
        </div>
      </div>

      <div class="flex gap-2 pt-2">
        <.button phx-click={@on_save} size="sm">Save Role</.button>
        <.button phx-click={@on_save} phx-value-edit="true" variant="outline" size="sm">
          Edit &amp; Save
        </.button>
      </div>
    </div>
    """
  end
end
