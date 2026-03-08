ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(ExCellenceServer.Repo, :manual)

# SaladUI requires TwMerge.Cache
TwMerge.Cache.start_link([])
