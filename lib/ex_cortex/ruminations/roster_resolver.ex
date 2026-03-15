defmodule ExCortex.Ruminations.RosterResolver do
  @moduledoc """
  Resolves roster patterns into concrete neuron specs.

  A roster entry is a map with a `"who"` key that identifies which neurons
  to use. This module handles all resolution patterns:

    - `"all"` — all active role neurons
    - `"apprentice"` / `"journeyman"` / `"master"` — rank-based lookup
    - `"team:X"` — team-based lookup
    - `"challenger"` — builtin neuron lookup
    - `"claude_haiku"` / `"claude_sonnet"` / `"claude_opus"` — inline spec
    - bare neuron ID string — direct Repo.get
    - `"preferred_who"` + rank combo — name+rank filter with fallback

  ## Public API

    - `resolve/1` — resolve a single roster entry (or "who" string) into neuron specs
    - `resolve_roster/1` — resolve a full roster list into enriched entries
  """

  import Ecto.Query

  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo

  @rank_values ["apprentice", "journeyman", "master"]

  @doc """
  Resolve a single roster entry map (or bare "who" string) into a list of neuron specs.

  Returns `[%{provider, model, system_prompt, name, tools}]`.
  """
  def resolve(%{"preferred_who" => name, "who" => rank} = step)
      when is_binary(name) and name != "" and rank in @rank_values do
    case from(m in Neuron,
           where:
             m.type == "role" and m.status == "active" and m.name == ^name and
               fragment("config->>'rank' = ?", ^rank)
         )
         |> Repo.all()
         |> Enum.map(&neuron_to_runner_spec/1) do
      [] -> resolve(%{step | "preferred_who" => nil})
      neurons -> neurons
    end
  end

  def resolve(%{"preferred_who" => name} = step) when is_binary(name) and name != "" do
    case from(m in Neuron,
           where: m.type == "role" and m.status == "active" and m.name == ^name
         )
         |> Repo.all()
         |> Enum.map(&neuron_to_runner_spec/1) do
      [] -> resolve(%{step | "preferred_who" => nil})
      neurons -> neurons
    end
  end

  def resolve(%{"who" => who}), do: resolve(who)
  def resolve(step) when is_map(step), do: resolve(Map.get(step, "who", "all"))

  def resolve("all") do
    from(m in Neuron, where: m.type == "role" and m.status == "active")
    |> Repo.all()
    |> Enum.map(&neuron_to_runner_spec/1)
  end

  def resolve("apprentice"), do: resolve_by_rank("apprentice")
  def resolve("journeyman"), do: resolve_by_rank("journeyman")
  def resolve("master"), do: resolve_by_rank("master")

  def resolve("challenger") do
    case ExCortex.Neurons.Builtin.get("challenger") do
      nil ->
        []

      neuron ->
        rank_config = neuron.ranks[:journeyman]

        [
          %{
            provider: "ollama",
            model: rank_config.model,
            system_prompt: neuron.system_prompt,
            name: neuron.name,
            tools: []
          }
        ]
    end
  end

  def resolve("team:" <> team) do
    from(m in Neuron,
      where: m.type == "role" and m.status == "active" and m.team == ^team
    )
    |> Repo.all()
    |> Enum.map(&neuron_to_runner_spec/1)
  end

  def resolve(claude_tier) when claude_tier in ["claude_haiku", "claude_sonnet", "claude_opus"] do
    [%{provider: "claude", model: claude_tier, name: claude_tier, system_prompt: nil, tools: []}]
  end

  def resolve(neuron_id) when is_binary(neuron_id) do
    case Repo.get(Neuron, neuron_id) do
      nil -> []
      m -> [neuron_to_runner_spec(m)]
    end
  end

  @doc """
  Resolve a full roster (list of roster entries) into enriched entries
  with their resolved neurons.

  Returns `[%{neurons: [...], when: "...", how: "..."}]`.
  """
  def resolve_roster(roster) when is_list(roster) do
    Enum.map(roster, fn step ->
      %{
        neurons: resolve(step),
        when: step["when"] || "parallel",
        how: step["how"] || "solo"
      }
    end)
  end

  # -- Private helpers --------------------------------------------------------

  defp resolve_by_rank(rank) do
    from(m in Neuron,
      where:
        m.type == "role" and m.status == "active" and
          fragment("config->>'rank' = ?", ^rank)
    )
    |> Repo.all()
    |> Enum.map(&neuron_to_runner_spec/1)
  end

  defp neuron_to_runner_spec(db) do
    %{
      provider: db.config["provider"] || "ollama",
      model: db.config["model"] || "phi4-mini",
      system_prompt: db.config["system_prompt"] || "",
      name: db.name,
      tools: resolve_member_tools(db.config["tools"])
    }
  end

  defp resolve_member_tools(nil), do: []
  defp resolve_member_tools("all_safe"), do: ExCortex.Tools.Registry.resolve_tools(:all_safe)
  defp resolve_member_tools("write"), do: ExCortex.Tools.Registry.resolve_tools(:write)
  defp resolve_member_tools("dangerous"), do: ExCortex.Tools.Registry.resolve_tools(:dangerous)
  defp resolve_member_tools("yolo"), do: ExCortex.Tools.Registry.resolve_tools(:dangerous)
  defp resolve_member_tools(names) when is_list(names), do: ExCortex.Tools.Registry.resolve_tools(names)
  defp resolve_member_tools(_), do: []
end
