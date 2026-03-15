defmodule ExCortex.Vision do
  @moduledoc "Routes vision requests to Ollama or Claude based on settings."

  alias ExCortex.Core.LLM.Ollama
  alias ExCortex.Settings

  def describe(image_path, prompt \\ "Describe this image in detail.") do
    image_b64 = image_path |> File.read!() |> Base.encode64()
    ext = image_path |> Path.extname() |> String.trim_leading(".") |> String.downcase()
    media_type = if ext in ~w(jpg jpeg), do: "image/jpeg", else: "image/#{ext}"

    case Settings.get(:vision_provider) || "ollama" do
      "claude" -> claude_vision(image_b64, media_type, prompt)
      _ -> ollama_vision(image_b64, prompt)
    end
  end

  defp ollama_vision(image_b64, prompt) do
    ollama_url = Application.get_env(:ex_cortex, :ollama_url, "http://127.0.0.1:11434")
    ollama_api_key = Application.get_env(:ex_cortex, :ollama_api_key)
    model = Settings.get(:ollama_vision_model) || "llava"
    ollama = Ollama.new(base_url: ollama_url, api_key: ollama_api_key)

    messages = [%{role: :user, content: prompt, images: [image_b64]}]

    case Ollama.chat(ollama, model, messages) do
      {:ok, text} when is_binary(text) -> {:ok, text}
      {:ok, %{content: text}} -> {:ok, text}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp claude_vision(image_b64, media_type, prompt) do
    api_key = Application.get_env(:ex_cortex, :anthropic_api_key)

    if !api_key do
      throw({:error, "ANTHROPIC_API_KEY not configured"})
    end

    body = %{
      model: "claude-haiku-4-5-20251001",
      max_tokens: 1024,
      messages: [
        %{
          role: "user",
          content: [
            %{type: "image", source: %{type: "base64", media_type: media_type, data: image_b64}},
            %{type: "text", text: prompt}
          ]
        }
      ]
    }

    case Req.post("https://api.anthropic.com/v1/messages",
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"},
             {"content-type", "application/json"}
           ]
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        {:ok, text}

      {:ok, %{body: body}} ->
        {:error, inspect(body)}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end
end
