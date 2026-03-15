defmodule ExCortex.Repo do
  use Ecto.Repo,
    otp_app: :ex_cortex,
    adapter: Ecto.Adapters.Postgres
end
