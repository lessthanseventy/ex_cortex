defmodule ExCalibur.LLMTest do
  use ExUnit.Case, async: true

  alias ExCalibur.LLM
  alias ExCalibur.LLM.Claude
  alias ExCalibur.LLM.Ollama

  describe "provider_for/1" do
    test "returns Ollama module for ollama provider" do
      assert LLM.provider_for("ollama") == Ollama
    end

    test "returns Claude module for claude provider" do
      assert LLM.provider_for("claude") == Claude
    end

    test "returns Ollama as default for nil" do
      assert LLM.provider_for(nil) == Ollama
    end

    test "returns Ollama as default for empty string" do
      assert LLM.provider_for("") == Ollama
    end

    test "returns Ollama as default for unknown provider" do
      assert LLM.provider_for("unknown") == Ollama
    end
  end

  describe "providers/0" do
    test "returns map of provider name to module" do
      providers = LLM.providers()
      assert providers["ollama"] == Ollama
      assert providers["claude"] == Claude
    end
  end

  describe "configured?/1" do
    test "ollama is configured by default" do
      assert LLM.configured?("ollama")
    end
  end
end
