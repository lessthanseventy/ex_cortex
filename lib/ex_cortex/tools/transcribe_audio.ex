defmodule ExCortex.Tools.TranscribeAudio do
  @moduledoc "Tool: transcribe audio to text (stub — requires whisper configuration)."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "transcribe_audio",
      description: "Transcribe an audio file to text using whisper. Requires whisper to be installed and configured.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Absolute path to the audio file (WAV, MP3, etc.)"}
        },
        "required" => ["path"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => _path}) do
    {:error, "Transcription not yet configured. Set vision_provider in settings and install whisper."}
  end
end
