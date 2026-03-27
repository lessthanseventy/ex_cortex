defmodule Mix.Tasks.DevTeam.Install do
  @shortdoc "Install Dev Team cluster + SI pipeline seeds"

  @moduledoc """
  Installs (or reinstalls) the Dev Team cluster: neurons, synapses, ruminations, and SI seeds.

      mix dev_team.install

  Safe to run after a DB reset or at any time — neurons use on_conflict: :nothing,
  synapses are skipped if a unique name conflict occurs, and RuminationSeed is idempotent.
  """

  use Mix.Task

  alias ExCortex.Neurons.Neuron

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    mod = ExCortex.Pathways.DevTeam

    IO.puts("Installing Dev Team neurons...")
    install_neurons(mod)

    IO.puts("Installing Dev Team synapses...")
    install_synapses(mod)

    IO.puts("Installing Dev Team ruminations...")
    install_ruminations(mod)

    IO.puts("Running SI rumination seed...")
    seed_si()

    IO.puts("Done.")
  end

  defp install_neurons(mod) do
    Enum.each(mod.resource_definitions(), fn attrs ->
      result =
        %Neuron{}
        |> Neuron.changeset(attrs)
        |> ExCortex.Repo.insert(on_conflict: :nothing)

      case result do
        {:ok, m} -> IO.puts("  + neuron: #{m.name} (#{m.config["rank"]})")
        {:error, _} -> IO.puts("  ~ skipped (already exists): #{attrs[:name] || attrs["name"]}")
      end
    end)
  end

  defp install_synapses(mod) do
    if function_exported?(mod, :synapse_definitions, 0) do
      Enum.each(mod.synapse_definitions(), &install_synapse/1)
    end
  end

  defp install_synapse(attrs) do
    case ExCortex.Ruminations.create_synapse(attrs) do
      {:ok, s} -> IO.puts("  + synapse: #{s.name}")
      {:error, cs} -> IO.puts("  ~ skipped synapse (#{attrs[:name] || attrs["name"]}): #{inspect(cs.errors)}")
    end
  end

  defp install_ruminations(mod) do
    if function_exported?(mod, :rumination_definitions, 0) do
      step_by_name = Map.new(ExCortex.Ruminations.list_synapses(), &{&1.name, &1.id})
      Enum.each(mod.rumination_definitions(), &install_rumination(&1, step_by_name))
    end
  end

  defp install_rumination(attrs, step_by_name) do
    steps =
      Enum.map(attrs.steps, fn step ->
        %{"step_id" => Map.get(step_by_name, step["thought_name"] || step["step_name"]), "flow" => step["flow"]}
      end)

    case ExCortex.Ruminations.create_rumination(Map.put(attrs, :steps, steps)) do
      {:ok, q} -> IO.puts("  + thought: #{q.name}")
      {:error, cs} -> IO.puts("  ~ skipped thought (#{attrs[:name] || attrs["name"]}): #{inspect(cs.errors)}")
    end
  end

  defp seed_si do
    case ExCortex.Neuroplasticity.Seed.seed() do
      {:ok, result} -> IO.puts("  SI seed ok: #{inspect(Map.keys(result))}")
      {:error, reason} -> IO.puts("  SI seed error: #{inspect(reason)}")
      other -> IO.puts("  SI seed: #{inspect(other)}")
    end
  end
end
