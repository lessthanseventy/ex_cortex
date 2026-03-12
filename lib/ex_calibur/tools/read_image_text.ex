defmodule ExCalibur.Tools.ReadImageText do
  @moduledoc "Tool: extract text from an image using OCR (tesseract or vision AI)."

  @ocr_prompt "Extract all text visible in this image. Return only the text, formatted as it appears."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_image_text",
      description:
        "Extract text from an image using OCR. Uses tesseract if available, otherwise falls back to vision AI.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Absolute path to the image file"}
        },
        "required" => ["path"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path}) do
    if File.exists?(path) do
      case try_tesseract(path) do
        {:ok, text} -> {:ok, text}
        {:unavailable} -> ExCalibur.Vision.describe(path, @ocr_prompt)
      end
    else
      {:error, "File not found: #{path}"}
    end
  end

  defp try_tesseract(path) do
    case System.cmd("which", ["tesseract"], stderr_to_stdout: true) do
      {_output, 0} ->
        case System.cmd("tesseract", [path, "stdout"], stderr_to_stdout: true) do
          {text, 0} -> {:ok, String.trim(text)}
          {error, _} -> {:error, error}
        end

      _ ->
        {:unavailable}
    end
  end
end
