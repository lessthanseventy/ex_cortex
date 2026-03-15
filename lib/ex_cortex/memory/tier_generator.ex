defmodule ExCortex.Memory.TierGenerator do
  @moduledoc "Generates L0 (impression) and L1 (recall) summaries for engrams."

  alias ExCortex.LLM
  alias ExCortex.Memory.Engram
  alias ExCortex.Repo

  @model "ministral-3:3b"

  def generate(%Engram{body: nil}), do: {:error, :no_body}
  def generate(%Engram{body: ""}), do: {:error, :no_body}

  def generate(%Engram{} = engram) do
    with {:ok, impression} <- generate_impression(engram),
         {:ok, recall} <- generate_recall(engram) do
      engram
      |> Engram.changeset(%{impression: impression, recall: recall})
      |> Repo.update()
    end
  end

  def generate_async(%Engram{} = engram) do
    Task.Supervisor.start_child(ExCortex.AsyncTaskSupervisor, fn ->
      generate(engram)
    end)
  end

  defp generate_impression(engram) do
    prompt = """
    Summarize the following in ONE sentence, max 100 tokens.
    Capture the essence — what is this about and why does it matter?

    Title: #{engram.title}
    Content: #{engram.body}
    """

    provider = LLM.provider_for(@model)

    case LLM.complete(provider, @model, "You are a summarizer.", prompt) do
      {:ok, text} when is_binary(text) -> {:ok, String.trim(text)}
      error -> {:error, error}
    end
  end

  defp generate_recall(engram) do
    prompt = """
    Create a structured summary of the following content in ~500-1000 tokens.
    Include section headings and key points. End with pointers to what detailed
    information is available if someone needs to go deeper.

    Title: #{engram.title}
    Content: #{engram.body}
    """

    provider = LLM.provider_for(@model)

    case LLM.complete(provider, @model, "You are a summarizer.", prompt) do
      {:ok, text} when is_binary(text) -> {:ok, String.trim(text)}
      error -> {:error, error}
    end
  end
end
