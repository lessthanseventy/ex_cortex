defmodule ExCortex.Tools.AnalyzeVideo do
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
      output_dir = ExCortex.Media.job_dir()

      with {:ok, _} <- ExCortex.Tools.ExtractFrames.call(%{"input" => path, "mode" => mode, "output_dir" => output_dir}) do
        timeline = build_timeline(output_dir)
        {:ok, build_result(timeline, path, output_dir, include_audio)}
      end
    else
      {:error, "File not found: #{path}"}
    end
  end

  defp build_timeline(output_dir) do
    output_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".jpg"))
    |> Enum.sort()
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {name, idx} -> describe_frame(Path.join(output_dir, name), idx) end)
  end

  defp describe_frame(frame_path, idx) do
    case ExCortex.Vision.describe(frame_path, "Briefly describe what is happening in this video frame.") do
      {:ok, desc} -> "Frame #{idx}: #{desc}"
      {:error, reason} -> "Frame #{idx}: [error: #{reason}]"
    end
  end

  defp build_result(timeline, _path, _output_dir, false), do: timeline

  defp build_result(timeline, path, output_dir, true) do
    case try_audio_transcription(path, output_dir) do
      {:ok, transcript} -> "#{timeline}\n\nAudio Transcript:\n#{transcript}"
      _ -> timeline
    end
  end

  defp try_audio_transcription(video_path, output_dir) do
    audio_path = Path.join(output_dir, "audio.wav")

    with {:ok, _} <-
           ExCortex.Tools.ExtractAudio.call(%{"input" => video_path, "output" => audio_path}),
         {:ok, transcript} <- ExCortex.Tools.TranscribeAudio.call(%{"path" => audio_path}) do
      {:ok, transcript}
    else
      _ -> {:error, :transcription_failed}
    end
  end
end
