defmodule ExCalibur.Sources.EmailSource do
  @moduledoc false
  @behaviour ExCalibur.Sources.Behaviour

  alias ExCalibur.Sources.SourceItem

  require Logger

  @impl true
  def init(_config) do
    {:ok, %{seen_thread_ids: MapSet.new()}}
  end

  @impl true
  def fetch(state, config) do
    with :ok <- sync_notmuch(),
         {:ok, threads} <- search_threads(config) do
      new_threads = Enum.reject(threads, &MapSet.member?(state.seen_thread_ids, &1["thread"]))

      items = Enum.flat_map(new_threads, &process_thread(&1, config))

      new_seen =
        Enum.reduce(new_threads, state.seen_thread_ids, fn t, acc ->
          MapSet.put(acc, t["thread"])
        end)

      {:ok, items, %{state | seen_thread_ids: new_seen}}
    else
      {:error, reason} ->
        Logger.warning("[EmailSource] fetch failed: #{inspect(reason)}")
        {:ok, [], state}
    end
  end

  defp process_thread(thread, config) do
    thread_id = thread["thread"]

    case fetch_thread(thread_id) do
      {:ok, body} ->
        :ok = tag_thread_seen(thread_id)

        [
          %SourceItem{
            source_id: config["source_id"],
            type: "email",
            content: body,
            metadata: %{subject: thread["subject"] || "", from: extract_from(thread)}
          }
        ]

      {:error, reason} ->
        Logger.warning("[EmailSource] Failed to fetch thread #{thread_id}: #{inspect(reason)}")
        []
    end
  end

  defp sync_notmuch do
    case System.cmd("notmuch", ["new"], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> {:error, "notmuch new exited #{code}: #{output}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp search_threads(config) do
    query = config["query"] || "tag:new"
    limit = config["limit"] || 50

    case System.cmd("notmuch", ["search", "--format=json", "--limit=#{limit}", query], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, threads} -> {:ok, threads}
          {:error, reason} -> {:error, "JSON decode failed: #{inspect(reason)}"}
        end

      {output, code} ->
        {:error, "notmuch search exited #{code}: #{output}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp fetch_thread(thread_id) do
    case System.cmd("notmuch", ["show", "--format=text", "--body=true", thread_id], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, "notmuch show exited #{code}: #{output}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp tag_thread_seen(thread_id) do
    case System.cmd("notmuch", ["tag", "-new", thread_id], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> Logger.warning("[EmailSource] tag -new failed for #{thread_id} (#{code}): #{output}")
    end

    :ok
  rescue
    e ->
      Logger.warning("[EmailSource] tag -new raised: #{Exception.message(e)}")
      :ok
  end

  defp extract_from(%{"authors" => authors}) when is_binary(authors), do: authors
  defp extract_from(_), do: ""
end
