defmodule ExCellenceServer.Repo do
  use Ecto.Repo,
    otp_app: :ex_cellence_server,
    adapter: Ecto.Adapters.Postgres
end
