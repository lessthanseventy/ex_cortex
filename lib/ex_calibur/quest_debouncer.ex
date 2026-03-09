defmodule ExCalibur.QuestDebouncer do
  @moduledoc """
  Coalesces items from multiple sources into a single quest or campaign run.

  When multiple sources fire (e.g. Sync All), each calls `enqueue/3` (for quests)
  or `enqueue_campaign/3` (for campaigns) with their items. The debouncer waits
  for a collection window, then summarises each source's batch with a quick LLM
  call, combines the summaries, and runs the quest or campaign exactly once.

  State keys are tagged tuples: {:quest, id} or {:campaign, id} to avoid collisions.
  """
  use GenServer

  alias ExCalibur.CampaignRunner
  alias ExCalibur.QuestRunner
  alias Excellence.LLM.Ollama

  require Logger

  @window_ms 20_000

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Enqueue items from a named source for a quest."
  def enqueue(quest, source_label, items) when is_list(items) and items != [] do
    GenServer.cast(__MODULE__, {:enqueue, {:quest, quest.id}, quest, source_label, items})
  end

  @doc "Enqueue items from a named source for a campaign."
  def enqueue_campaign(campaign, source_label, items) when is_list(items) and items != [] do
    GenServer.cast(__MODULE__, {:enqueue, {:campaign, campaign.id}, campaign, source_label, items})
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
          ExCalibur.PubSub,
          "source_activity",
          {:quest_started, entity_name, total_items}
        )

        Task.Supervisor.start_child(ExCalibur.SourceTaskSupervisor, fn ->
          try do
            Logger.info(
              "[QuestDebouncer] Summarising #{map_size(batches)} source(s) for #{inspect(key)} (#{entity_name}), #{total_items} total items"
            )

            combined = summarise_batches(batches)
            Logger.info("[QuestDebouncer] Running #{inspect(key)} (#{entity_name})")

            case key do
              {:quest, _} -> QuestRunner.run(entity, combined)
              {:campaign, _} -> CampaignRunner.run(entity, combined)
            end
          rescue
            e ->
              Logger.error("Quest/Campaign failed: #{Exception.message(e)}")

              Phoenix.PubSub.broadcast(
                ExCalibur.PubSub,
                "source_activity",
                {:quest_error, entity_name, Exception.message(e)}
              )
          end
        end)

        {:noreply, state}
    end
  end

  # ── Per-source summarisation ───────────────────────────────────────────────

  defp summarise_batches(batches) do
    ollama_url = Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434")
    ollama = Ollama.new(base_url: ollama_url)

    batches
    |> Enum.map(fn {label, items} -> summarise_source(label, items, ollama) end)
    |> Enum.join("\n\n")
  end

  defp summarise_source(label, items, ollama) do
    raw =
      items
      |> Enum.map(&item_headline/1)
      |> Enum.join("\n")

    prompt = """
    You are a concise news analyst. Summarise the following items from "#{label}" in 2–4 sentences,
    focusing on the most market-relevant information for a BTC price analysis.
    Be factual. No fluff.

    Items:
    #{String.slice(raw, 0, 3_000)}
    """

    messages = [%{role: :user, content: prompt}]

    case Ollama.chat(ollama, "phi4-mini", messages) do
      {:ok, %{content: text}} ->
        "## #{label}\n#{String.slice(text, 0, 400)}"

      {:ok, text} when is_binary(text) ->
        "## #{label}\n#{String.slice(text, 0, 400)}"

      _ ->
        Logger.warning("[QuestDebouncer] Summarisation failed for source '#{label}', using headlines")
        "## #{label}\n#{String.slice(raw, 0, 400)}"
    end
  end

  defp item_headline(%{metadata: %{title: title}} = item) when is_binary(title) and title != "" do
    snippet = item.content |> String.replace(title, "") |> String.trim() |> String.slice(0, 100)
    if snippet == "", do: "- #{title}", else: "- #{title}: #{snippet}"
  end

  defp item_headline(item), do: "- #{String.slice(item.content, 0, 150)}"
end
