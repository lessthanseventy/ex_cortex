defmodule ExCalibur.Sources.MediaSource do
  @moduledoc false
  @behaviour ExCalibur.Sources.Behaviour

  alias ExCalibur.Sources.SourceItem

  require Logger

  @impl true
  def init(config) do
    url = config["url"] || ""

    if url == "" do
      {:error, "url is required for media source"}
    else
      {:ok, %{seen_video_ids: MapSet.new()}}
    end
  end

  @impl true
  def fetch(state, config) do
    url = config["url"]

    case list_videos(url) do
      {:ok, videos} ->
        new_videos = Enum.reject(videos, &MapSet.member?(state.seen_video_ids, &1.id))

        items =
          Enum.map(new_videos, fn video ->
            %SourceItem{
              source_id: config["source_id"],
              type: "video",
              content: "New video: #{video.title}\n#{video.url}",
              metadata: %{title: video.title, url: video.url, video_id: video.id}
            }
          end)

        new_seen =
          Enum.reduce(videos, state.seen_video_ids, fn v, acc ->
            MapSet.put(acc, v.id)
          end)

        {:ok, items, %{state | seen_video_ids: new_seen}}

      {:error, reason} ->
        Logger.warning("[MediaSource] fetch failed: #{inspect(reason)}")
        {:ok, [], state}
    end
  end

  defp list_videos(url) do
    case System.cmd("yt-dlp", ["--flat-playlist", "--dump-json", url], stderr_to_stdout: true) do
      {output, 0} ->
        videos = output |> String.split("\n", trim: true) |> Enum.flat_map(&decode_video_line/1)
        {:ok, videos}

      {output, code} ->
        {:error, "yt-dlp exited #{code}: #{output}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp decode_video_line(line) do
    case Jason.decode(line) do
      {:ok, entry} -> [parse_video_entry(entry)]
      {:error, _} -> []
    end
  end

  defp parse_video_entry(entry) do
    id = entry["id"] || entry["webpage_url_basename"] || ""
    title = entry["title"] || ""
    video_url = entry["url"] || entry["webpage_url"] || ""

    %{id: id, title: title, url: video_url}
  end
end
