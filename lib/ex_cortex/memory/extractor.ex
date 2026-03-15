defmodule ExCortex.Memory.Extractor do
  @moduledoc "Extracts structured engrams from completed rumination runs."

  alias ExCortex.Memory

  def extract(rumination_run) do
    # Always create episodic (what happened)
    {:ok, episodic} = create_episodic(rumination_run)

    {:ok, [episodic]}
  end

  defp create_episodic(rumination_run) do
    summary = summarize_run(rumination_run)
    tag = rumination_run.rumination_name |> String.downcase() |> String.replace(~r/\s+/, "-")

    Memory.create_engram(%{
      title: "#{rumination_run.rumination_name} ##{rumination_run.id}",
      body: summary,
      category: "episodic",
      source: "extraction",
      cluster_name: Map.get(rumination_run, :cluster_name),
      daydream_id: rumination_run.id,
      importance: 2,
      tags: ["rumination-run", tag]
    })
  end

  defp summarize_run(rumination_run) do
    impulse_summary =
      Enum.map_join(rumination_run[:impulses] || [], "\n", fn i ->
        "Step #{i[:step] || i.step}: #{inspect(i[:results] || i.results)}"
      end)

    "Rumination: #{rumination_run.rumination_name}\nStatus: #{rumination_run.status}\n\n#{impulse_summary}"
  end
end
