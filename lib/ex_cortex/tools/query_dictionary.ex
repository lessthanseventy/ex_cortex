defmodule ExCortex.Tools.QueryDictionary do
  @moduledoc "Tool: search a named dictionary for matching rows or lines."

  alias ExCortex.Library

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "query_dictionary",
      description:
        "Search a reference dictionary by name. Returns matching rows (CSV) or lines (text/markdown) that contain the query string.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "dictionary" => %{
            "type" => "string",
            "description" => "Exact name of the dictionary to search"
          },
          "query" => %{
            "type" => "string",
            "description" => "Search term (case-insensitive)"
          }
        },
        "required" => ["dictionary", "query"]
      },
      callback: &call/1
    )
  end

  def call(%{"dictionary" => name, "query" => query}) do
    case Library.get_dictionary_by_name(name) do
      nil -> {:error, "Dictionary '#{name}' not found"}
      dict -> {:ok, search(dict, query)}
    end
  end

  defp search(%{content_type: "csv", name: name, content: content}, query) do
    q = String.downcase(query)
    [header | rows] = String.split(content, "\n", trim: true)
    matches = Enum.filter(rows, fn row -> String.contains?(String.downcase(row), q) end)

    if matches == [] do
      "No matches found in \"#{name}\"."
    else
      "Found #{length(matches)} match(es) in \"#{name}\":\n\n#{header}\n#{Enum.join(matches, "\n")}"
    end
  end

  defp search(%{name: name, content: content}, query) do
    q = String.downcase(query)

    matches =
      content
      |> String.split("\n", trim: true)
      |> Enum.filter(fn line -> String.contains?(String.downcase(line), q) end)

    if matches == [] do
      "No matches found in \"#{name}\"."
    else
      "Found #{length(matches)} match(es) in \"#{name}\":\n\n#{Enum.join(matches, "\n")}"
    end
  end
end
