defmodule ExCortexWeb.EvaluateLive do
  @moduledoc false
  use ExCortexWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: "/ruminations")}
  end

  @impl true
  def render(assigns), do: ~H""
end
