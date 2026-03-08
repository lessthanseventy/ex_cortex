defmodule ExCellenceServerWeb.PipelinesLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import ExCellenceUI.Components.PipelineBuilder
  import ExCellenceUI.Components.TemplatePicker

  alias Excellence.Schemas.ResourceDefinition

  @templates %{
    "Content Moderation" => Excellence.Templates.ContentModeration,
    "Code Review" => Excellence.Templates.CodeReview,
    "Risk Assessment" => Excellence.Templates.RiskAssessment
  }

  @impl true
  def mount(_params, _session, socket) do
    templates =
      Enum.map(@templates, fn {_name, mod} ->
        meta = mod.metadata()

        %{
          name: meta.name,
          description: meta.description,
          roles: Enum.map(meta.roles, & &1.name),
          actions: Enum.map(meta.actions, &to_string/1),
          strategy: inspect(meta.strategy)
        }
      end)

    {:ok,
     assign(socket,
       templates: templates,
       building: false,
       pipeline: [],
       page_title: "Pipelines"
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("install_template", %{"template" => template_name}, socket) do
    case Map.get(@templates, template_name) do
      nil ->
        {:noreply, put_flash(socket, :error, "Template not found")}

      mod ->
        resource_defs = mod.resource_definitions()

        Enum.each(resource_defs, fn attrs ->
          %ResourceDefinition{}
          |> ResourceDefinition.changeset(attrs)
          |> ExCellenceServer.Repo.insert(on_conflict: :nothing)
        end)

        {:noreply, put_flash(socket, :info, "Template '#{template_name}' installed!")}
    end
  end

  @impl true
  def handle_event("toggle_builder", _, socket) do
    {:noreply, assign(socket, building: !socket.assigns.building)}
  end

  @impl true
  def handle_event("save_pipeline", _, socket) do
    {:noreply, put_flash(socket, :info, "Pipeline saved")}
  end

  @impl true
  def handle_event("add_middleware", %{"module" => module}, socket) do
    stage = %{name: module |> String.split(".") |> List.last(), module: module}
    {:noreply, assign(socket, pipeline: socket.assigns.pipeline ++ [stage])}
  end

  @impl true
  def handle_event("remove_middleware", %{"index" => index}, socket) do
    idx = String.to_integer(index)
    {:noreply, assign(socket, pipeline: List.delete_at(socket.assigns.pipeline, idx))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Pipelines</h1>
        <.button phx-click="toggle_builder">
          {if @building, do: "Close Builder", else: "Build Pipeline"}
        </.button>
      </div>

      <%= if @building do %>
        <.pipeline_builder pipeline={@pipeline} on_save="save_pipeline" />
      <% end %>

      <div>
        <h2 class="text-lg font-semibold mb-4">Templates</h2>
        <.template_picker templates={@templates} on_install="install_template" />
      </div>
    </div>
    """
  end
end
