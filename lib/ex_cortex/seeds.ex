defmodule ExCortex.Seeds do
  @moduledoc "Seeds the database with starter clusters, neurons, ruminations, engrams, signals, senses, and axioms."

  require Logger

  def seed do
    Logger.info("[Seeds] Seeding ExCortex...")
    seed_clusters()
    seed_neurons()
    seed_ruminations()
    seed_engrams()
    seed_axioms()
    seed_signals()
    seed_senses()
    Logger.info("[Seeds] Done.")
  end

  defp seed_clusters, do: :ok
  defp seed_neurons, do: :ok
  defp seed_ruminations, do: :ok
  defp seed_engrams, do: :ok
  defp seed_axioms, do: :ok
  defp seed_signals, do: :ok
  defp seed_senses, do: :ok
end
