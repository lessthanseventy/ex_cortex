defmodule ExCortex.Tools.DescribeImage do
  @moduledoc "Tool: describe an image using vision AI (Ollama or Claude)."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "describe_image",
      description: "Describe the contents of an image file using vision AI. Supports JPEG, PNG, GIF, and WebP.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Absolute path to the image file"},
          "prompt" => %{
            "type" => "string",
            "description" => "Custom prompt for the vision model (default: 'Describe this image in detail.')"
          }
        },
        "required" => ["path"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path} = params) do
    prompt = Map.get(params, "prompt", "Describe this image in detail.")

    if File.exists?(path) do
      ExCortex.Vision.describe(path, prompt)
    else
      {:error, "File not found: #{path}"}
    end
  end
end
