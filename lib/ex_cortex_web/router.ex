defmodule ExCortexWeb.Router do
  use ExCortexWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExCortexWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :assign_banner
  end

  defp assign_banner(conn, _opts) do
    assign(conn, :banner, ExCortex.Settings.get_banner())
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ExCortexWeb do
    pipe_through :api
    post "/webhooks/:sense_id", WebhookController, :receive
  end

  scope "/", ExCortexWeb do
    pipe_through :browser

    live_session :default, layout: {ExCortexWeb.Layouts, :app} do
      # Brain vocabulary routes (new TUI screens)
      live "/", CortexLive, :index
      live "/cortex", CortexLive, :index
      live "/neurons", NeuronsLive, :index
      live "/thoughts", ThoughtsLive, :index
      live "/memory", MemoryLive, :index
      live "/senses", SensesLive, :index
      live "/instinct", InstinctLive, :index

      # Legacy routes (kept for backwards compatibility)
      live "/lodge", LodgeLive, :index
      live "/quests", QuestsLive, :index
      live "/quest-board", QuestsLive, :index
      live "/thought-board", QuestsLive, :index
      live "/town-square", TownSquareLive, :index
      live "/guild-hall", GuildHallLive, :index
      live "/cluster-hall", GuildHallLive, :index
      live "/grimoire", GrimoireLive, :index
      live "/library", LibraryLive, :index
      live "/evaluate", EvaluateLive, :index
      live "/guide", GuideLive, :index
      live "/settings", SettingsLive
    end
  end
end
