defmodule ExCellenceServerWeb.QuestsLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import ExCellenceUI.Components.CharterPicker
  import ExCellenceUI.Components.PipelineBuilder

  alias Excellence.Schemas.ResourceDefinition

  @charters %{
    "Content Moderation" => Excellence.Charters.ContentModeration,
    "Code Review" => Excellence.Charters.CodeReview,
    "Risk Assessment" => Excellence.Charters.RiskAssessment
  }

  @impl true
  def mount(_params, _session, socket) do
    charters =
      Enum.map(@charters, fn {_name, mod} ->
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
       charters: charters,
       building: false,
       pipeline: [],
       page_title: "Quests"
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("install_charter", %{"charter" => charter_name}, socket) do
    case Map.get(@charters, charter_name) do
      nil ->
        {:noreply, put_flash(socket, :error, "Charter not found")}

      mod ->
        resource_defs = mod.resource_definitions()

        Enum.each(resource_defs, fn attrs ->
          %ResourceDefinition{}
          |> ResourceDefinition.changeset(attrs)
          |> ExCellenceServer.Repo.insert(on_conflict: :nothing)
        end)

        {:noreply, put_flash(socket, :info, "Charter '#{charter_name}' installed!")}
    end
  end

  @impl true
  def handle_event("toggle_builder", _, socket) do
    {:noreply, assign(socket, building: !socket.assigns.building)}
  end

  @impl true
  def handle_event("save_pipeline", _, socket) do
    {:noreply, put_flash(socket, :info, "Quest saved")}
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
        <h1 class="text-2xl font-bold">Quests</h1>
        <.button phx-click="toggle_builder">
          {if @building, do: "Close Planner", else: "Plan Quest"}
        </.button>
      </div>

      <%= if @building do %>
        <.pipeline_builder pipeline={@pipeline} on_save="save_pipeline" />
      <% end %>

      <div>
        <h2 class="text-lg font-semibold mb-4">Charters</h2>
        <.charter_picker charters={@charters} on_install="install_charter" />
      </div>
    </div>
    """
  end
end
