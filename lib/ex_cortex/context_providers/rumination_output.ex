defmodule ExCortex.ContextProviders.RuminationOutput do
  @moduledoc """
  Injects the output of the most recent completed daydream of a named rumination.

  Config:
    "rumination"           - rumination name to look up (required)
    "synapses"             - list of synapse indices to include, e.g. [0, 1] (default: all)
    "label"                - section header
    "max_bytes_per_synapse" - per-synapse output truncation (default: 2000)

  Example:
    %{"type" => "rumination_output", "rumination" => "SI: Analyst Sweep", "synapses" => [0, 1]}
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  import Ecto.Query

  alias ExCortex.Repo
  alias ExCortex.Ruminations.Daydream
  alias ExCortex.Ruminations.Rumination

  require Logger

  @default_max_bytes 2_000

  @impl true
  def build(config, _rumination, _input) do
    case Map.get(config, "rumination") do
      nil ->
        Logger.warning("[RuminationOutputCtx] No 'rumination' name in config")
        ""

      rumination_name ->
        fetch_output(rumination_name, config)
    end
  end

  defp fetch_output(rumination_name, config) do
    label = Map.get(config, "label", "## Previous Rumination Output: #{rumination_name}")
    synapse_indices = Map.get(config, "synapses") || Map.get(config, "steps")
    max_bytes = Map.get(config, "max_bytes_per_synapse") || Map.get(config, "max_bytes_per_step", @default_max_bytes)

    with %Rumination{id: rumination_id} <- Repo.one(from t in Rumination, where: t.name == ^rumination_name, limit: 1),
         %Daydream{synapse_results: results} <- latest_daydream(rumination_id) do
      format_output(label, results, synapse_indices, max_bytes)
    else
      nil ->
        Logger.debug("[RuminationOutputCtx] No completed daydream found for rumination: #{rumination_name}")
        ""
    end
  end

  defp latest_daydream(rumination_id) do
    Repo.one(
      from d in Daydream,
        where: d.rumination_id == ^rumination_id and d.status == "complete",
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
            [format_synapse_section(idx, data, status, max_bytes)]

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

  defp format_synapse_section(idx, data, status, max_bytes) do
    truncated = String.slice(data, 0, max_bytes)
    suffix = if byte_size(data) > max_bytes, do: "\n... (truncated)", else: ""
    "### Synapse #{idx} (#{status})\n#{truncated}#{suffix}"
  end
end
