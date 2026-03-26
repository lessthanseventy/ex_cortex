defmodule ExCortex.Memory.EmbeddingsTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Memory.Embeddings

  describe "embed_text/1" do
    test "returns error for empty text" do
      assert {:error, :empty_input} = Embeddings.embed_text("")
      assert {:error, :empty_input} = Embeddings.embed_text(nil)
    end

    test "returns a vector or ollama_unavailable for valid text" do
      case Embeddings.embed_text("test embedding input") do
        {:ok, vector} ->
          assert is_list(vector)
          assert length(vector) == 768
          assert Enum.all?(vector, &is_float/1)

        {:error, :ollama_unavailable} ->
          :ok

        {:error, :ollama_error} ->
          :ok
      end
    end
  end

  describe "embed_engram/1" do
    test "generates embedding from title + impression" do
      {:ok, engram} =
        ExCortex.Memory.create_engram(%{
          title: "Test engram for embedding",
          impression: "A test engram used to verify embedding generation",
          category: "semantic"
        })

      case Embeddings.embed_engram(engram) do
        {:ok, updated} ->
          assert updated.embedding

        {:error, :ollama_unavailable} ->
          :ok

        {:error, :ollama_error} ->
          :ok
      end
    end
  end
end
