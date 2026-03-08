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

    live "/", LodgeLive, :index
    live "/guild-hall", GuildHallLive, :index
    live "/members", MembersLive, :index
    live "/members/new", MembersLive, :new
    live "/members/:id/edit", MembersLive, :edit
    live "/quests", QuestsLive, :index
    live "/quests/new", QuestsLive, :new
    live "/evaluate", EvaluateLive, :index
    live "/lodge", LodgeLive, :index
  end
end
