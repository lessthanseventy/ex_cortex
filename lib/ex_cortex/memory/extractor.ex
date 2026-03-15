defmodule ExCortex.Memory.Extractor do
  @moduledoc "Extracts structured engrams from completed thought runs."

  alias ExCortex.Memory

  def extract(thought_run) do
    # Always create episodic (what happened)
    {:ok, episodic} = create_episodic(thought_run)

    {:ok, [episodic]}
  end

  defp create_episodic(thought_run) do
    summary = summarize_run(thought_run)
    tag = thought_run.thought_name |> String.downcase() |> String.replace(~r/\s+/, "-")

    Memory.create_engram(%{
      title: "#{thought_run.thought_name} ##{thought_run.id}",
      body: summary,
      category: "episodic",
      source: "extraction",
      cluster_name: thought_run[:cluster_name],
      daydream_id: thought_run.id,
      importance: 2,
      tags: ["thought-run", tag]
    })
  end

  defp summarize_run(thought_run) do
    impulse_summary =
      Enum.map_join(thought_run[:impulses] || [], "\n", fn i ->
        "Step #{i[:step] || i.step}: #{inspect(i[:results] || i.results)}"
      end)

    "Thought: #{thought_run.thought_name}\nStatus: #{thought_run.status}\n\n#{impulse_summary}"
  end
end
