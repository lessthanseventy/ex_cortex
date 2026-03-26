defmodule ExCortex.Memory.Embeddings do
  @moduledoc "Generate and store vector embeddings for engrams via Ollama."

  alias ExCortex.Memory.Engram
  alias ExCortex.Repo
  alias ExCortex.Settings

  require Logger

  @default_model "nomic-embed-text"

  def embed_text(nil), do: {:error, :empty_input}
  def embed_text(""), do: {:error, :empty_input}

  def embed_text(text) when is_binary(text) do
    model = Settings.resolve(:embedding_model, default: @default_model)
    url = Settings.resolve(:ollama_url, default: "http://127.0.0.1:11434")

    case Req.post("#{url}/api/embed", json: %{model: model, input: text}) do
      {:ok, %{status: 200, body: %{"embeddings" => [vector | _]}}} ->
        {:ok, vector}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Embeddings] Ollama returned #{status}: #{inspect(body)}")
        {:error, :ollama_error}

      {:error, %{reason: reason}} ->
        Logger.debug("[Embeddings] Ollama unavailable: #{inspect(reason)}")
        {:error, :ollama_unavailable}
    end
  end

  def embed_engram(%Engram{} = engram) do
    text = embedding_text(engram)

    case embed_text(text) do
      {:ok, vector} ->
        engram
        |> Ecto.Changeset.change(%{embedding: vector})
        |> Repo.update()

      error ->
        error
    end
  end

  def embed_engram_async(%Engram{} = engram) do
    Task.Supervisor.start_child(ExCortex.AsyncTaskSupervisor, fn ->
      embed_engram(engram)
    end)
  end

  defp embedding_text(%Engram{title: title, impression: impression}) do
    [title, impression || ""]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end
end
