defmodule ExCortex.Senses.EmailSense do
  @moduledoc "Polls a local notmuch instance for new email threads."
  @behaviour ExCortex.Senses.Behaviour

  alias ExCortex.Senses.Item

  require Logger

  @impl true
  def init(_config) do
    case System.cmd("notmuch", ["--version"], stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, %{last_timestamp: -1}}

      {_output, _code} ->
        {:error, "notmuch binary not found or not working"}
    end
  rescue
    ErlangError -> {:error, "notmuch binary not found — install notmuch to use the email sense"}
  end

  @impl true
  def fetch(state, config) do
    query = config["query"] || "tag:inbox AND tag:unread"
    max_results = config["max_results"] || 50
    last_timestamp = state[:last_timestamp] || state["last_timestamp"] || 0

    sort = config["sort"] || "oldest-first"

    case search_threads(query, max_results, sort) do
      {:ok, threads} ->
        new_threads =
          threads
          |> Enum.filter(&((&1["timestamp"] || 0) > last_timestamp))
          |> Enum.sort_by(& &1["timestamp"])

        if new_threads == [] do
          Logger.debug("[EmailSense] No new threads for query: #{query}")
          {:ok, [], state}
        else
          items = Enum.flat_map(new_threads, &process_thread(&1, config))

          new_last_timestamp =
            new_threads
            |> Enum.map(& &1["timestamp"])
            |> Enum.max(fn -> last_timestamp end)

          {:ok, items, %{state | last_timestamp: new_last_timestamp}}
        end

      {:error, reason} ->
        Logger.warning("[EmailSense] Search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp search_threads(query, max_results, sort) do
    args = [
      "search",
      "--format=json",
      "--output=summary",
      "--sort=#{sort}",
      "--limit=#{max_results}",
      query
    ]

    case System.cmd("notmuch", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, threads} when is_list(threads) -> {:ok, threads}
          {:ok, _} -> {:error, "unexpected notmuch search output format"}
          {:error, reason} -> {:error, "JSON parse failed: #{inspect(reason)}"}
        end

      {output, code} ->
        {:error, "notmuch search exited #{code}: #{String.trim(output)}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp process_thread(thread, config) do
    thread_id = thread["thread"]
    subject = thread["subject"] || "(no subject)"
    authors = thread["authors"] || ""
    date_relative = thread["date_relative"] || ""
    tags = thread["tags"] || []
    total = thread["total"] || 0

    case fetch_thread_body(thread_id) do
      {:ok, body} ->
        content =
          format_email(
            subject: subject,
            authors: authors,
            date_relative: date_relative,
            tags: tags,
            total: total,
            body: body
          )

        [
          %Item{
            source_id: config["source_id"],
            type: "email",
            content: content,
            metadata: %{
              thread_id: thread_id,
              subject: subject,
              from: authors,
              tags: tags,
              timestamp: thread["timestamp"]
            }
          }
        ]

      {:error, reason} ->
        Logger.warning("[EmailSense] Failed to fetch thread #{thread_id}: #{inspect(reason)}")
        []
    end
  end

  defp fetch_thread_body(thread_id) do
    case System.cmd("notmuch", ["show", "--format=json", thread_id], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, data} -> {:ok, extract_latest_body(data)}
          {:error, reason} -> {:error, "JSON parse failed: #{inspect(reason)}"}
        end

      {output, code} ->
        {:error, "notmuch show exited #{code}: #{String.trim(output)}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # notmuch show --format=json returns a nested list structure:
  # [[[ {message}, [replies] ], ...]]
  # We want the body of the latest (last) message in the thread.
  defp extract_latest_body(data) when is_list(data) do
    data
    |> List.flatten()
    |> Enum.filter(&is_map/1)
    |> Enum.map(&extract_body_from_message/1)
    |> List.last() || ""
  end

  defp extract_latest_body(_), do: ""

  defp extract_body_from_message(%{"body" => body}) when is_list(body) do
    body
    |> Enum.flat_map(&extract_content_parts/1)
    |> Enum.join("\n")
  end

  defp extract_body_from_message(_), do: ""

  defp extract_content_parts(%{"content-type" => "text/plain", "content" => content}) when is_binary(content) do
    [content]
  end

  defp extract_content_parts(%{"content" => parts}) when is_list(parts) do
    Enum.flat_map(parts, &extract_content_parts/1)
  end

  defp extract_content_parts(_), do: []

  defp format_email(opts) do
    tags_str = Enum.join(opts[:tags], ", ")

    String.trim("""
    Subject: #{opts[:subject]}
    From: #{opts[:authors]}
    Date: #{opts[:date_relative]}
    Tags: #{tags_str}
    Thread: #{opts[:total]} messages

    ---
    #{String.trim(opts[:body])}
    """)
  end
end
