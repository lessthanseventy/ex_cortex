defmodule ExCortex.Tools.ExtractAudio do
  @moduledoc "Tool: extract audio from a video or media file using ffmpeg."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "extract_audio",
      description: "Extract audio from a video or media file as a 16kHz mono WAV file using ffmpeg.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "input" => %{"type" => "string", "description" => "Absolute path to the input media file"},
          "output" => %{
            "type" => "string",
            "description" =>
              "Absolute path for the output WAV file (optional, defaults to input path with .wav extension)"
          }
        },
        "required" => ["input"]
      },
      callback: &call/1
    )
  end

  def call(%{"input" => input} = params) do
    output = Map.get(params, "output", Path.rootname(input) <> ".wav")
    args = ["-i", input, "-vn", "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1", output, "-y"]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end
end
