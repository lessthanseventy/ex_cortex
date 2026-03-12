defmodule ExCalibur.Tools.DownloadMedia do
  @moduledoc "Tool: download media (video/audio) from a URL using yt-dlp."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "download_media",
      description:
        "Download video or audio from a URL using yt-dlp (supports YouTube, SoundCloud, and many other sites).",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "url" => %{"type" => "string", "description" => "URL of the media to download"}
        },
        "required" => ["url"]
      },
      callback: &call/1
    )
  end

  def call(%{"url" => url}) do
    dir = ExCalibur.Media.job_dir()
    args = ["-o", "#{dir}/%(title)s.%(ext)s", "--no-playlist", url]

    case System.cmd("yt-dlp", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Downloaded to #{dir}\n#{output}"}
      {error, _} -> {:error, error}
    end
  end
end
