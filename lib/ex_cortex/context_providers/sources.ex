defmodule ExCortex.ContextProviders.Sources do
  @moduledoc """
  Injects a summary of available data sources, axioms, and memory count.

  No config options needed — always returns the full inventory.
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  import Ecto.Query

  alias ExCortex.Repo

  @impl true
  def build(_config, _thought, _input) do
    senses =
      from(s in ExCortex.Senses.Sense, where: s.status != "error", order_by: s.name)
      |> Repo.all()
      |> Enum.map(fn s ->
        status = if s.status == "paused", do: " [paused]", else: ""

        last =
          if s.last_run_at,
            do: " (last checked #{Calendar.strftime(s.last_run_at, "%Y-%m-%d %H:%M")})",
            else: ""

        "- #{s.source_type}: \"#{s.name}\"#{status}#{last}"
      end)

    axioms = Enum.map(ExCortex.Lexicon.list_axioms(), fn a -> "- #{a.name}" end)
    engram_count = Repo.aggregate(ExCortex.Memory.Engram, :count)

    sections = ["## Available Data Sources"]
    sections = if senses == [], do: sections, else: sections ++ ["### Senses\n" <> Enum.join(senses, "\n")]
    sections = if axioms == [], do: sections, else: sections ++ ["### Axioms\n" <> Enum.join(axioms, "\n")]
    sections = sections ++ ["### Memory\n- #{engram_count} engrams in store"]

    Enum.join(sections, "\n\n")
  end
end
