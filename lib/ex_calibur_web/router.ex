defmodule ExCaliburWeb.Router do
  use ExCaliburWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExCaliburWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ExCaliburWeb do
    pipe_through :api
    post "/webhooks/:source_id", WebhookController, :receive
  end

  scope "/", ExCaliburWeb do
    pipe_through :browser

    live "/", LodgeLive, :index
    live "/guild-hall", GuildHallLive, :index
    live "/town-square", TownSquareLive, :index
    live "/members", MembersLive, :index
    live "/quests", QuestsLive, :index
    live "/library", LibraryLive, :index
    live "/stacks", StacksLive, :index
    live "/evaluate", EvaluateLive, :index
    live "/lodge", LodgeLive, :index
  end
end
