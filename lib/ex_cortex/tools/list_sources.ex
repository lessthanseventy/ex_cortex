defmodule ExCortex.Tools.ListSources do
  @moduledoc "Tool: discover configured data sources, axioms, and memory stats."

  import Ecto.Query

  alias ExCortex.Lexicon.Axiom
  alias ExCortex.Memory.Engram
  alias ExCortex.Repo
  alias ExCortex.Senses.Sense

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "list_sources",
      description: """
      Discover what data sources are available. Returns configured senses (email, obsidian, github, feeds, etc.),
      axioms (reference datasets in the Lexicon), and engram (memory) statistics.
      Call this when you need to understand what data the user has access to before using other tools.
      No parameters required.
      """,
      parameter_schema: %{
        "type" => "object",
        "properties" => %{},
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(_params) do
    result = %{
      senses: list_senses(),
      axioms: list_axioms(),
      engram_stats: engram_stats()
    }

    {:ok, Jason.encode!(result, pretty: true)}
  end

  defp list_senses do
    from(s in Sense, order_by: s.name)
    |> Repo.all()
    |> Enum.map(fn s ->
      %{
        name: s.name,
        type: s.source_type,
        status: s.status,
        last_run: s.last_run_at && Calendar.strftime(s.last_run_at, "%Y-%m-%d %H:%M UTC")
      }
    end)
  end

  defp list_axioms do
    from(a in Axiom, order_by: a.name)
    |> Repo.all()
    |> Enum.map(fn a -> %{name: a.name, content_type: a.content_type} end)
  end

  defp engram_stats do
    total = Repo.aggregate(Engram, :count)

    by_category =
      from(e in Engram,
        group_by: e.category,
        select: {e.category, count(e.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{total: total, by_category: by_category}
  end
end
