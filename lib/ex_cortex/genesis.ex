defmodule ExCortex.Genesis do
  @moduledoc """
  AI pipeline builder.

  Takes a natural language description, gathers context about available
  clusters and neurons, calls an LLM to propose a pipeline, then creates
  the rumination and synapses in the database.

      ExCortex.Genesis.synthesize("Summarise new Elixir blog posts daily")
      #=> {:ok, %Rumination{}}
  """

  import Ecto.Query

  alias ExCortex.Clusters
  alias ExCortex.LLM
  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo
  alias ExCortex.Ruminations
  alias ExCortex.Settings

  require Logger

  @valid_output_types ~w(freeform verdict artifact signal)

  @doc """
  Synthesize a rumination pipeline from a natural language description.

  ## Options

    * `:model` — LLM model identifier (default: auto-selected)
    * `:provider` — LLM provider string (default: auto-selected)

  Returns `{:ok, %Rumination{}}` or `{:error, reason}`.
  """
  def synthesize(description, opts \\ []) do
    {default_provider, default_model} = default_model()
    provider = Keyword.get(opts, :provider, default_provider)
    model = Keyword.get(opts, :model, default_model)

    context = gather_context()
    system_prompt = build_system_prompt(context)

    Logger.info("Genesis: calling #{provider}/#{model} for pipeline: #{String.slice(description, 0, 80)}")

    with {:ok, parsed} <- call_llm(system_prompt, description, provider, model),
         {:ok, rumination} <- create_pipeline(parsed) do
      Logger.info("Genesis: created rumination #{rumination.id} — #{rumination.name}")
      {:ok, rumination}
    end
  end

  @doc """
  Returns available models for the forge UI selector.
  """
  def available_models do
    ollama_models = [
      %{provider: "ollama", model: "devstral-small-2:24b", label: "Devstral (local, reliable)"},
      %{provider: "ollama", model: "ministral-3:8b", label: "Ministral (local, fast)"}
    ]

    claude_models =
      case Settings.resolve(:anthropic_api_key, env_var: "ANTHROPIC_API_KEY") do
        key when is_binary(key) and key != "" ->
          [
            %{provider: "claude", model: "claude_opus", label: "Claude Opus (strongest)"},
            %{provider: "claude", model: "claude_sonnet", label: "Claude Sonnet (balanced)"},
            %{provider: "claude", model: "claude_haiku", label: "Claude Haiku (fast)"}
          ]

        _ ->
          []
      end

    claude_models ++ ollama_models
  end

  # ---------------------------------------------------------------------------
  # Context gathering
  # ---------------------------------------------------------------------------

  defp gather_context do
    clusters = Clusters.list_pathways()

    neurons =
      Repo.all(
        from(n in Neuron,
          where: n.type == "role" and n.status == "active",
          order_by: [asc: n.team, asc: n.name]
        )
      )

    cluster_lines =
      Enum.map(clusters, fn c ->
        cluster_neurons = Enum.filter(neurons, &(&1.team == c.cluster_name))

        neuron_names =
          Enum.map_join(cluster_neurons, ", ", fn n ->
            rank = get_in(n.config, ["rank"])
            "#{n.name} (#{rank})"
          end)

        "- #{c.cluster_name}: #{neuron_names}"
      end)

    Enum.join(cluster_lines, "\n")
  end

  # ---------------------------------------------------------------------------
  # System prompt
  # ---------------------------------------------------------------------------

  defp build_system_prompt(context) do
    """
    You are a pipeline architect for ExCortex, an AI agent orchestration platform.

    Vocabulary:
    - Rumination = a multi-step pipeline
    - Synapse = a single step in a pipeline
    - Cluster = an agent team
    - Neuron = an agent/role within a cluster

    Available clusters and neurons:
    #{context}

    Your task: given a user's description of what they want automated, design a pipeline.
    Pick appropriate clusters and neurons for each step.

    Output ONLY valid JSON (no markdown fences, no commentary) with this exact structure:

    {
      "name": "Pipeline Name",
      "description": "What this pipeline does",
      "steps": [
        {
          "name": "Step: Action Name",
          "description": "What this step does",
          "cluster_name": "ClusterName",
          "preferred_neuron": "NeuronName",
          "output_type": "freeform"
        }
      ]
    }

    Valid output_type values: freeform, verdict, artifact, signal
    - freeform: general text output (default)
    - verdict: a pass/fail decision
    - artifact: stores result in memory as an engram
    - signal: pushes a card to the dashboard

    The last step's output_type determines where the final result goes:
    - signal → appears on the dashboard
    - artifact → saved to memory

    All forged pipelines use trigger "manual".
    Design 2-6 steps. Each step name should start with "Step: ".
    """
  end

  # ---------------------------------------------------------------------------
  # LLM call
  # ---------------------------------------------------------------------------

  defp call_llm(system_prompt, user_description, provider, model) do
    case LLM.complete(provider, model, system_prompt, user_description) do
      {:ok, response} -> parse_response(response)
      {:error, _} = error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Response parsing
  # ---------------------------------------------------------------------------

  defp parse_response(response) do
    response
    |> strip_code_fences()
    |> String.trim()
    |> Jason.decode()
    |> case do
      {:ok, %{"name" => _, "steps" => steps} = parsed} when is_list(steps) and steps != [] ->
        {:ok, parsed}

      {:ok, _} ->
        {:error, :invalid_response}

      {:error, _} ->
        {:error, :invalid_response}
    end
  end

  defp strip_code_fences(text) do
    text
    |> String.replace(~r/\A\s*```(?:json)?\s*\n/, "")
    |> String.replace(~r/\n\s*```\s*\z/, "")
  end

  # ---------------------------------------------------------------------------
  # Pipeline creation
  # ---------------------------------------------------------------------------

  def create_pipeline(parsed) do
    with {:ok, synapses} <- create_synapses(parsed["steps"]) do
      step_entries =
        synapses
        |> Enum.with_index(1)
        |> Enum.map(fn {s, order} -> %{"step_id" => s.id, "order" => order} end)

      Ruminations.create_rumination(%{
        name: parsed["name"],
        description: parsed["description"] || "AI-generated pipeline",
        trigger: "manual",
        status: "paused",
        steps: step_entries
      })
    end
  end

  defp create_synapses(steps) do
    results =
      Enum.map(steps, fn step ->
        output_type = validated_output_type(step["output_type"])

        Ruminations.create_synapse(%{
          name: step["name"],
          description: step["description"],
          trigger: "manual",
          output_type: output_type,
          cluster_name: step["cluster_name"],
          roster: [
            %{
              "who" => "all",
              "preferred_who" => step["preferred_neuron"],
              "how" => "solo",
              "when" => "sequential"
            }
          ]
        })
      end)

    case Enum.find(results, fn {status, _} -> status == :error end) do
      nil -> {:ok, Enum.map(results, fn {:ok, s} -> s end)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp validated_output_type(type) when type in @valid_output_types, do: type
  defp validated_output_type(_), do: "freeform"

  # ---------------------------------------------------------------------------
  # Default model selection
  # ---------------------------------------------------------------------------

  defp default_model do
    case Settings.resolve(:anthropic_api_key, env_var: "ANTHROPIC_API_KEY") do
      key when is_binary(key) and key != "" -> {"claude", "claude_sonnet"}
      _ -> {"ollama", "devstral-small-2:24b"}
    end
  end
end
