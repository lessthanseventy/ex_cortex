defmodule Mix.Tasks.DevTeam.Install do
  @shortdoc "Install Dev Team cluster + SI pipeline seeds"

  @moduledoc """
  Installs (or reinstalls) the Dev Team cluster: neurons, synapses, thoughts, and SI seeds.

      mix dev_team.install

  Safe to run after a DB reset or at any time — neurons use on_conflict: :nothing,
  synapses are skipped if a unique name conflict occurs, and ThoughtSeed is idempotent.
  """

  use Mix.Task

  alias ExCortex.Neurons.Neuron

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    mod = ExCortex.Pathways.DevTeam

    IO.puts("Installing Dev Team neurons...")
    install_members(mod)

    IO.puts("Installing Dev Team synapses (thoughts)...")
    install_steps(mod)

    IO.puts("Installing Dev Team campaigns...")
    install_campaigns(mod)

    IO.puts("Running SI thought seed...")
    seed_si()

    IO.puts("Done.")
  end

  defp install_members(mod) do
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

  defp install_steps(mod) do
    if function_exported?(mod, :quest_definitions, 0) do
      Enum.each(mod.quest_definitions(), fn attrs ->
        case ExCortex.Thoughts.create_synapse(attrs) do
          {:ok, s} -> IO.puts("  + step: #{s.name}")
          {:error, cs} -> IO.puts("  ~ skipped step (#{attrs[:name] || attrs["name"]}): #{inspect(cs.errors)}")
        end
      end)
    end
  end

  defp install_campaigns(mod) do
    if function_exported?(mod, :campaign_definitions, 0) do
      step_by_name = Map.new(ExCortex.Thoughts.list_synapses(), &{&1.name, &1.id})

      Enum.each(mod.campaign_definitions(), fn attrs ->
        steps =
          Enum.map(attrs.steps, fn step ->
            %{"step_id" => Map.get(step_by_name, step["thought_name"] || step["step_name"]), "flow" => step["flow"]}
          end)

        case ExCortex.Thoughts.create_thought(Map.put(attrs, :steps, steps)) do
          {:ok, q} -> IO.puts("  + campaign: #{q.name}")
          {:error, cs} -> IO.puts("  ~ skipped campaign (#{attrs[:name] || attrs["name"]}): #{inspect(cs.errors)}")
        end
      end)
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
