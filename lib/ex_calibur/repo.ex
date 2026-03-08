defmodule ExCalibur.Repo do
  use Ecto.Repo,
    otp_app: :ex_calibur,
    adapter: Ecto.Adapters.Postgres
end
