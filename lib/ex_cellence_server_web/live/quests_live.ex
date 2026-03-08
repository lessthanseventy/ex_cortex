defmodule ExCellenceServerWeb.QuestsLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import ExCellenceUI.Components.PipelineBuilder

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
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
    </div>
    """
  end
end
