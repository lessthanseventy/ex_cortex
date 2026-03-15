defmodule ExCortex.Memory.Extractor do
  @moduledoc "Extracts structured engrams from completed rumination runs."

  alias ExCortex.Memory

  def extract(rumination_run) do
    {:ok, episodic} = create_episodic(rumination_run)
    {:ok, [episodic]}
  end

  defp create_episodic(rumination_run) do
    dry_run? = Map.get(rumination_run, :dry_run, false)
    summary = summarize_run(rumination_run)
    tag = rumination_run.rumination_name |> String.downcase() |> String.replace(~r/\s+/, "-")

    title_prefix = if dry_run?, do: "[DRY RUN] ", else: ""
    base_tags = ["rumination-run", tag]
    tags = if dry_run?, do: ["dry-run" | base_tags], else: base_tags

    Memory.create_engram(%{
      title: "#{title_prefix}#{rumination_run.rumination_name} ##{rumination_run.id}",
      body: summary,
      category: "episodic",
      source: "extraction",
      cluster_name: Map.get(rumination_run, :cluster_name),
      daydream_id: rumination_run.id,
      importance: if(dry_run?, do: 1, else: 2),
      tags: tags
    })
  end

  defp summarize_run(rumination_run) do
    dry_label = if Map.get(rumination_run, :dry_run, false), do: " (DRY RUN — no actions taken)", else: ""

    impulse_summary =
      Enum.map_join(rumination_run[:impulses] || [], "\n", fn i ->
        "Step #{i[:step] || i.step}: #{inspect(i[:results] || i.results)}"
      end)

    "Rumination: #{rumination_run.rumination_name}#{dry_label}\nStatus: #{rumination_run.status}\n\n#{impulse_summary}"
  end
end
