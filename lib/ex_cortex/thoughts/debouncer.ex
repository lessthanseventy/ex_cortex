defmodule ExCortex.Thoughts.Debouncer do
  @moduledoc """
  Coalesces items from multiple sources into a single step or daydream.

  When multiple sources fire (e.g. Sync All), each calls `enqueue/3` (for steps)
  or `enqueue_thought/3` (for thoughts) with their items. The debouncer waits
  for a collection window, then summarises each source's batch with a quick LLM
  call, combines the summaries, and runs the step or thought exactly once.

  State keys are tagged tuples: {:step, id} or {:thought, id} to avoid collisions.
  """
  use GenServer

  alias ExCortex.Thoughts.ImpulseRunner
  alias ExCortex.Thoughts.Runner

  require Logger

  @window_ms 20_000

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Enqueue items from a named source for a step."
  def enqueue(step, source_label, items) when is_list(items) and items != [] do
    GenServer.cast(__MODULE__, {:enqueue, {:step, step.id}, step, source_label, items})
  end

  @doc "Enqueue items from a named source for a thought."
  def enqueue_thought(thought, source_label, items) when is_list(items) and items != [] do
    GenServer.cast(__MODULE__, {:enqueue, {:thought, thought.id}, thought, source_label, items})
  end

  # ── GenServer callbacks ────────────────────────────────────────────────────

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:enqueue, key, entity, source_label, items}, state) do
    state =
      case Map.get(state, key) do
        nil ->
          Process.send_after(self(), {:fire, key}, @window_ms)
          Map.put(state, key, %{entity: entity, batches: %{source_label => items}})

        existing ->
          existing_source_items = Map.get(existing.batches, source_label, [])
          updated_batches = Map.put(existing.batches, source_label, existing_source_items ++ items)
          Map.put(state, key, %{existing | batches: updated_batches})
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:fire, key}, state) do
    case Map.pop(state, key) do
      {nil, state} ->
        {:noreply, state}

      {%{entity: entity, batches: batches}, state} ->
        total_items = batches |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
        entity_name = entity.name

        Phoenix.PubSub.broadcast(
          ExCortex.PubSub,
          "source_activity",
          {:thought_started, entity_name, total_items}
        )

        Task.Supervisor.start_child(ExCortex.SourceTaskSupervisor, fn ->
          try do
            Logger.info(
              "[ThoughtDebouncer] Summarising #{map_size(batches)} source(s) for #{inspect(key)} (#{entity_name}), #{total_items} total items"
            )

            combined = summarise_batches(batches)
            Logger.info("[ThoughtDebouncer] Running #{inspect(key)} (#{entity_name})")

            case key do
              {:step, _} -> ImpulseRunner.run(entity, combined)
              {:thought, _} -> Runner.run(entity, combined)
            end
          rescue
            e ->
              Logger.error("Step/Thought failed: #{Exception.message(e)}")

              Phoenix.PubSub.broadcast(
                ExCortex.PubSub,
                "source_activity",
                {:thought_error, entity_name, Exception.message(e)}
              )
          end
        end)

        {:noreply, state}
    end
  end

  # ── Per-source summarisation ───────────────────────────────────────────────

  defp summarise_batches(batches) do
    Enum.map_join(batches, "\n\n", fn {label, items} -> summarise_source(label, items) end)
  end

  defp summarise_source(label, items) do
    raw = Enum.map_join(items, "\n\n", &item_headline/1)
    "## #{label}\n\n#{String.slice(raw, 0, 4_000)}"
  end

  defp item_headline(%{metadata: %{title: title}} = item) when is_binary(title) and title != "" do
    snippet = item.content |> String.replace(title, "") |> String.trim() |> String.slice(0, 100)
    if snippet == "", do: "- #{title}", else: "- #{title}: #{snippet}"
  end

  defp item_headline(item), do: "- #{String.slice(item.content, 0, 150)}"
end
