defmodule ExCalibur.Sources.FeedWatcher do
  @moduledoc false
  @behaviour ExCalibur.Sources.Behaviour

  alias ExCalibur.Sources.SourceItem

  @impl true
  def init(config) do
    {:ok, %{last_seen_ids: Map.get(config, "last_seen_ids", [])}}
  end

  @impl true
  def fetch(state, config) do
    url = config["url"]

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        entries = parse_feed(body)
        new_entries = Enum.reject(entries, &(&1.id in state.last_seen_ids))

        items =
          Enum.map(new_entries, fn entry ->
            %SourceItem{
              source_id: config["source_id"],
              type: "feed_entry",
              content: "#{entry.title}\n\n#{entry.description}",
              metadata: %{title: entry.title, link: entry.link, published_at: entry.published_at}
            }
          end)

        new_state = %{state | last_seen_ids: entries |> Enum.map(& &1.id) |> Enum.take(100)}
        {:ok, items, new_state}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_feed(body) when is_binary(body) do
    cond do
      String.contains?(body, "<entry>") -> parse_atom(body)
      String.contains?(body, "<item>") -> parse_rss(body)
      true -> []
    end
  end

  defp parse_feed(_), do: []

  defp parse_rss(body) do
    ~r/<item>(.*?)<\/item>/s
    |> Regex.scan(body)
    |> Enum.map(fn [_, item_xml] ->
      %{
        id:
          extract_tag(item_xml, "guid") || extract_tag(item_xml, "link") ||
            :md5 |> :crypto.hash(item_xml) |> Base.encode16(),
        title: extract_tag(item_xml, "title") || "",
        description: extract_tag(item_xml, "description") || "",
        link: extract_tag(item_xml, "link") || "",
        published_at: extract_tag(item_xml, "pubDate") || ""
      }
    end)
  end

  defp parse_atom(body) do
    ~r/<entry>(.*?)<\/entry>/s
    |> Regex.scan(body)
    |> Enum.map(fn [_, entry_xml] ->
      %{
        id: extract_tag(entry_xml, "id") || :md5 |> :crypto.hash(entry_xml) |> Base.encode16(),
        title: extract_tag(entry_xml, "title") || "",
        description: extract_tag(entry_xml, "summary") || extract_tag(entry_xml, "content") || "",
        link: extract_attr(entry_xml, "link", "href") || "",
        published_at: extract_tag(entry_xml, "published") || extract_tag(entry_xml, "updated") || ""
      }
    end)
  end

  defp extract_tag(xml, tag) do
    case Regex.run(~r/<#{tag}[^>]*>(.*?)<\/#{tag}>/s, xml) do
      [_, content] -> content |> String.trim() |> __MODULE__.HtmlEntities.decode()
      _ -> nil
    end
  end

  defp extract_attr(xml, tag, attr) do
    case Regex.run(~r/<#{tag}[^>]*#{attr}="([^"]*)"/, xml) do
      [_, value] -> value
      _ -> nil
    end
  end

  defmodule HtmlEntities do
    @moduledoc false
    def decode(str) do
      str
      |> String.replace("&amp;", "&")
      |> String.replace("&lt;", "<")
      |> String.replace("&gt;", ">")
      |> String.replace("&quot;", "\"")
      |> String.replace("&#39;", "'")
      |> String.replace(~r/<!\[CDATA\[(.*?)\]\]>/s, "\\1")
    end
  end
end
