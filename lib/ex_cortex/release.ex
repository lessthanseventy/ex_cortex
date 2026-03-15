defmodule ExCortex.Release do
  @moduledoc false
  @app :ex_cortex

  require Logger

  def migrate do
    load_app()

    for repo <- repos() do
      ensure_database(repo)
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp ensure_database(repo) do
    case repo.__adapter__().storage_up(repo.config()) do
      :ok -> Logger.info("Database created for #{inspect(repo)}")
      {:error, :already_up} -> :ok
      {:error, reason} -> Logger.warning("Could not create database: #{inspect(reason)}")
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
