defmodule ExCalibur.Tools.ExtractFrames do
  @moduledoc "Tool: extract frames from a video file using ffmpeg."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "extract_frames",
      description: "Extract frames from a video file using ffmpeg. Supports keyframe-only or interval-based extraction.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "input" => %{"type" => "string", "description" => "Absolute path to the input video file"},
          "mode" => %{
            "type" => "string",
            "description" => "Extraction mode: 'keyframes' (I-frames only, default) or 'interval' (one frame per N seconds)",
            "enum" => ["keyframes", "interval"]
          },
          "interval_seconds" => %{"type" => "integer", "description" => "Seconds between frames when mode is 'interval' (default 5)"},
          "output_dir" => %{"type" => "string", "description" => "Directory to save extracted frames (optional, auto-generated if omitted)"}
        },
        "required" => ["input"]
      },
      callback: &call/1
    )
  end

  def call(%{"input" => input} = params) do
    mode = Map.get(params, "mode", "keyframes")
    dir = Map.get(params, "output_dir", ExCalibur.Media.job_dir())
    File.mkdir_p!(dir)

    vf =
      case mode do
        "interval" ->
          n = Map.get(params, "interval_seconds", 5)
          "fps=1/#{n}"

        _ ->
          "select=eq(ptype\\,I)"
      end

    args = ["-i", input, "-vf", vf, "-vsync", "vfr", "#{dir}/frame_%04d.jpg", "-y"]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} ->
        frames =
          dir
          |> File.ls!()
          |> Enum.filter(&String.ends_with?(&1, ".jpg"))
          |> Enum.sort()

        {:ok, "Extracted #{length(frames)} frames to #{dir}"}

      {error, _} ->
        {:error, error}
    end
  end
end
