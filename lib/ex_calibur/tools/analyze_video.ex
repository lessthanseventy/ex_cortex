defmodule ExCalibur.Tools.AnalyzeVideo do
  @moduledoc "Tool: analyze a video by extracting frames and describing each using vision AI."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "analyze_video",
      description:
        "Analyze a video file by extracting frames and describing each with vision AI. Optionally extracts and transcribes audio.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Absolute path to the video file"},
          "mode" => %{
            "type" => "string",
            "description" =>
              "Frame extraction mode: 'keyframes' (I-frames only, default) or 'interval' (one frame per 5s)",
            "enum" => ["keyframes", "interval"]
          },
          "include_audio" => %{
            "type" => "boolean",
            "description" => "Whether to also extract and transcribe audio (default: false)"
          }
        },
        "required" => ["path"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path} = params) do
    if File.exists?(path) do
      mode = Map.get(params, "mode", "keyframes")
      include_audio = Map.get(params, "include_audio", false)
      output_dir = ExCalibur.Media.job_dir()

      with {:ok, _extract_msg} <-
             ExCalibur.Tools.ExtractFrames.call(%{
               "input" => path,
               "mode" => mode,
               "output_dir" => output_dir
             }) do
        frames =
          output_dir
          |> File.ls!()
          |> Enum.filter(&String.ends_with?(&1, ".jpg"))
          |> Enum.sort()

        frame_descriptions =
          frames
          |> Enum.with_index(1)
          |> Enum.map(fn {frame_name, idx} ->
            frame_path = Path.join(output_dir, frame_name)

            case ExCalibur.Vision.describe(frame_path, "Briefly describe what is happening in this video frame.") do
              {:ok, desc} -> "Frame #{idx}: #{desc}"
              {:error, reason} -> "Frame #{idx}: [error: #{reason}]"
            end
          end)

        timeline = Enum.join(frame_descriptions, "\n")

        result =
          if include_audio do
            audio_result = try_audio_transcription(path, output_dir)

            case audio_result do
              {:ok, transcript} -> "#{timeline}\n\nAudio Transcript:\n#{transcript}"
              _ -> timeline
            end
          else
            timeline
          end

        {:ok, result}
      end
    else
      {:error, "File not found: #{path}"}
    end
  end

  defp try_audio_transcription(video_path, output_dir) do
    audio_path = Path.join(output_dir, "audio.wav")

    with {:ok, _} <-
           ExCalibur.Tools.ExtractAudio.call(%{"input" => video_path, "output" => audio_path}),
         {:ok, transcript} <- ExCalibur.Tools.TranscribeAudio.call(%{"path" => audio_path}) do
      {:ok, transcript}
    else
      _ -> {:error, :transcription_failed}
    end
  end
end
