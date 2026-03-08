defmodule ExCellenceServerWeb.EvaluateLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: "/quests")}
  end

  @impl true
  def render(assigns), do: ~H""
end
