defmodule ExCellenceServerWeb.Router do
  use ExCellenceServerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExCellenceServerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", ExCellenceServerWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/roles", RolesLive, :index
    live "/roles/new", RolesLive, :new
    live "/roles/:id/edit", RolesLive, :edit
    live "/pipelines", PipelinesLive, :index
    live "/pipelines/new", PipelinesLive, :new
    live "/evaluate", EvaluateLive, :index
    live "/dashboard", DashboardLive, :index
  end
end
