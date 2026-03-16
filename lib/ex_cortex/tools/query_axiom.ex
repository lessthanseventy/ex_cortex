defmodule ExCortex.Tools.QueryAxiom do
  @moduledoc "Tool: search a named axiom for matching rows or lines."

  alias ExCortex.Lexicon

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "query_axiom",
      description:
        ~s{Search a reference axiom (dataset) by exact name. Axioms are CSV or text reference data in the Lexicon. Use list_sources to discover available axiom names. Case-insensitive substring search on content. Example: query_axiom(axiom: "tech-glossary", query: "elixir")},
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "axiom" => %{
            "type" => "string",
            "description" => "Exact name of the axiom to search"
          },
          "query" => %{
            "type" => "string",
            "description" => "Search term (case-insensitive)"
          }
        },
        "required" => ["axiom", "query"]
      },
      callback: &call/1
    )
  end

  def call(%{"axiom" => name, "query" => query}) do
    case Lexicon.get_axiom_by_name(name) do
      nil -> {:error, "Axiom '#{name}' not found"}
      axiom -> {:ok, search(axiom, query)}
    end
  end

  # Support old parameter name for backwards compat with existing DB configs
  def call(%{"dictionary" => name, "query" => query}), do: call(%{"axiom" => name, "query" => query})

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
