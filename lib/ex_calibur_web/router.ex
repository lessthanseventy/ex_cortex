defmodule ExCaliburWeb.Router do
  use ExCaliburWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExCaliburWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :assign_banner
  end

  defp assign_banner(conn, _opts) do
    assign(conn, :banner, ExCalibur.Settings.get_banner())
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

    live_session :default, layout: {ExCaliburWeb.Layouts, :app} do
      live "/", LodgeLive, :index
      live "/town-square", TownSquareLive, :index
      live "/guild-hall", GuildHallLive, :index
      live "/quests", QuestsLive, :index
      live "/quest-board", QuestsLive, :index
      live "/grimoire", GrimoireLive, :index
      live "/library", LibraryLive, :index
      live "/evaluate", EvaluateLive, :index
      live "/lodge", LodgeLive, :index
      live "/guide", GuideLive, :index
      live "/settings", SettingsLive
    end
  end
end
