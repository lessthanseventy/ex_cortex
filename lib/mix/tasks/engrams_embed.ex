defmodule Mix.Tasks.Engrams.Embed do
  @shortdoc "Generate embeddings for engrams missing them"
  @moduledoc "Backfill embeddings for existing engrams."
  use Mix.Task

  import Ecto.Query

  alias ExCortex.Memory.Embeddings
  alias ExCortex.Memory.Engram
  alias ExCortex.Repo

  require Logger

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    engrams =
      Repo.all(
        from(e in Engram,
          where: is_nil(e.embedding),
          order_by: [desc: e.importance, desc: e.inserted_at]
        )
      )

    total = length(engrams)
    Logger.info("[Embed] Backfilling #{total} engrams...")

    engrams
    |> Enum.with_index(1)
    |> Enum.each(fn {engram, idx} ->
      embed_and_log(engram, idx, total)
      Process.sleep(50)
    end)

    Logger.info("[Embed] Backfill complete.")
  end

  defp embed_and_log(engram, idx, total) do
    case Embeddings.embed_engram(engram) do
      {:ok, _} ->
        if rem(idx, 10) == 0, do: Logger.info("[Embed] #{idx}/#{total} done")

      {:error, reason} ->
        Logger.warning("[Embed] Failed #{engram.id} (#{engram.title}): #{inspect(reason)}")
    end
  end
end
