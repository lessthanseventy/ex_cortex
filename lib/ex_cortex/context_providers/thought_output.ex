defmodule ExCortex.ContextProviders.ThoughtOutput do
  @moduledoc """
  Injects the output of the most recent completed daydream of a named thought.

  Config:
    "thought"              - thought name to look up (required)
    "synapses"             - list of synapse indices to include, e.g. [0, 1] (default: all)
    "label"                - section header
    "max_bytes_per_synapse" - per-synapse output truncation (default: 2000)

  Example:
    %{"type" => "thought_output", "thought" => "SI: Analyst Sweep", "synapses" => [0, 1]}
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  import Ecto.Query

  alias ExCortex.Repo
  alias ExCortex.Thoughts.Daydream
  alias ExCortex.Thoughts.Thought

  require Logger

  @default_max_bytes 2_000

  @impl true
  def build(config, _thought, _input) do
    case Map.get(config, "thought") || Map.get(config, "thought") do
      nil ->
        Logger.warning("[ThoughtOutputCtx] No 'thought' name in config")
        ""

      thought_name ->
        fetch_output(thought_name, config)
    end
  end

  defp fetch_output(thought_name, config) do
    label = Map.get(config, "label", "## Previous Thought Output: #{thought_name}")
    synapse_indices = Map.get(config, "synapses") || Map.get(config, "steps")
    max_bytes = Map.get(config, "max_bytes_per_synapse") || Map.get(config, "max_bytes_per_step", @default_max_bytes)

    with %Thought{id: thought_id} <- Repo.one(from t in Thought, where: t.name == ^thought_name, limit: 1),
         %Daydream{synapse_results: results} <- latest_daydream(thought_id) do
      format_output(label, results, synapse_indices, max_bytes)
    else
      nil ->
        Logger.debug("[ThoughtOutputCtx] No completed daydream found for thought: #{thought_name}")
        ""
    end
  end

  defp latest_daydream(thought_id) do
    Repo.one(
      from d in Daydream,
        where: d.thought_id == ^thought_id and d.status == "complete",
        order_by: [desc: d.inserted_at],
        limit: 1
    )
  end

  defp format_output(label, synapse_results, nil, max_bytes) do
    indices =
      synapse_results
      |> Map.keys()
      |> Enum.map(&String.to_integer/1)
      |> Enum.sort()

    format_output(label, synapse_results, indices, max_bytes)
  end

  defp format_output(label, synapse_results, indices, max_bytes) do
    sections =
      Enum.flat_map(indices, fn idx ->
        case Map.get(synapse_results, to_string(idx)) do
          %{"data" => data, "status" => status} when is_binary(data) ->
            truncated = String.slice(data, 0, max_bytes)
            suffix = if byte_size(data) > max_bytes, do: "\n... (truncated)", else: ""
            ["### Synapse #{idx} (#{status})\n#{truncated}#{suffix}"]

          _ ->
            []
        end
      end)

    if sections == [] do
      ""
    else
      "#{label}\n\n#{Enum.join(sections, "\n\n")}"
    end
  end
end
