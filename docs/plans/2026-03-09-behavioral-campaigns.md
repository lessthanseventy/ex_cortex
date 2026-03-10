# Behavioral Campaigns Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Campaign the primary active entity that owns a trigger (source/scheduled/manual), contains ordered quest steps, and runs them sequentially when triggered — quests become reusable step definitions.

**Architecture:** Campaign holds trigger/schedule/source_ids just like Quest does today. `CampaignRunner.run/2` resolves each step's quest_id, runs them in sequence via `QuestRunner.run/2`, threading each result as additional context into the next step. ScheduledQuestRunner, SourceWorker, and QuestDebouncer are each extended to also handle campaigns alongside quests. Quests continue to work standalone — no migration needed.

**Tech Stack:** Elixir/Phoenix, Ecto, GenServer (QuestDebouncer), existing QuestRunner, Crontab (cron matching)

---

## Task 1: `Quests.list_campaigns_for_source/1`

**Files:**
- Modify: `lib/ex_calibur/quests.ex`
- Test: `test/ex_calibur/quests_test.exs`

**Step 1: Write the failing test**

In `test/ex_calibur/quests_test.exs`, add to the `campaigns` describe block:

```elixir
test "list_campaigns_for_source returns active source-triggered campaigns" do
  {:ok, c1} =
    Quests.create_campaign(%{
      name: "Campaign Source",
      trigger: "source",
      source_ids: ["src-abc"],
      status: "active"
    })

  # Paused campaign — should NOT appear
  {:ok, _c2} =
    Quests.create_campaign(%{
      name: "Paused Campaign",
      trigger: "source",
      source_ids: ["src-abc"],
      status: "paused"
    })

  # Different source — should NOT appear
  {:ok, _c3} =
    Quests.create_campaign(%{
      name: "Other Campaign",
      trigger: "source",
      source_ids: ["src-xyz"],
      status: "active"
    })

  assert [%Campaign{id: id}] = Quests.list_campaigns_for_source("src-abc")
  assert id == c1.id
end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur/quests_test.exs --seed 0' --pane=main:1.3
```

Expected: `** (UndefinedFunctionError) function ExCalibur.Quests.list_campaigns_for_source/1 is undefined`

**Step 3: Implement**

In `lib/ex_calibur/quests.ex`, add after `list_quests_for_source/1`:

```elixir
def list_campaigns_for_source(source_id) do
  Repo.all(
    from c in Campaign,
      where:
        c.trigger == "source" and
          c.status == "active" and
          fragment("? = ANY(?)", ^source_id, c.source_ids)
  )
end
```

**Step 4: Run tests to verify pass**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur/quests_test.exs --seed 0' --pane=main:1.3
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add lib/ex_calibur/quests.ex test/ex_calibur/quests_test.exs
git commit -m "feat: add Quests.list_campaigns_for_source/1"
```

---

## Task 2: `CampaignRunner`

**Files:**
- Create: `lib/ex_calibur/campaign_runner.ex`
- Create: `test/ex_calibur/campaign_runner_test.exs`

**Background:** `QuestRunner.run/2` returns `{:ok, %{artifact: attrs}}` for artifact quests or `{:ok, %{verdict:, steps:}}` for verdict quests. `CampaignRunner` resolves steps in order, runs each quest, then formats the result as text to inject into the next step's input.

**Step 1: Write the failing test**

```elixir
# test/ex_calibur/campaign_runner_test.exs
defmodule ExCalibur.CampaignRunnerTest do
  use ExCalibur.DataCase, async: false

  alias ExCalibur.CampaignRunner
  alias ExCalibur.Quests

  test "run/2 executes each step quest in order and returns final result" do
    # Create two quests
    {:ok, q1} =
      Quests.create_quest(%{
        name: "Step 1 Quest",
        trigger: "manual",
        output_type: "artifact",
        roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]
      })

    {:ok, q2} =
      Quests.create_quest(%{
        name: "Step 2 Quest",
        trigger: "manual",
        output_type: "artifact",
        roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]
      })

    {:ok, campaign} =
      Quests.create_campaign(%{
        name: "Two-Step Campaign",
        trigger: "manual",
        steps: [
          %{"quest_id" => to_string(q1.id), "order" => 1},
          %{"quest_id" => to_string(q2.id), "order" => 2}
        ]
      })

    # No members in test DB → QuestRunner returns {:error, :no_members}
    # CampaignRunner should still return a result (even if each step errors)
    result = CampaignRunner.run(campaign, "test input")
    assert match?({:ok, _} | {:error, _}, result)
  end

  test "run/2 with empty steps returns ok with empty result" do
    {:ok, campaign} =
      Quests.create_campaign(%{name: "Empty Campaign", trigger: "manual", steps: []})

    assert {:ok, %{steps: []}} = CampaignRunner.run(campaign, "input")
  end

  test "result_to_text/1 formats artifact result as markdown" do
    result = {:ok, %{artifact: %{title: "My Title", body: "Some body text"}}}
    text = CampaignRunner.result_to_text(result)
    assert String.contains?(text, "My Title")
    assert String.contains?(text, "Some body text")
  end

  test "result_to_text/1 formats verdict result as summary" do
    result = {:ok, %{verdict: "pass", steps: []}}
    text = CampaignRunner.result_to_text(result)
    assert String.contains?(text, "pass")
  end
end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur/campaign_runner_test.exs --seed 0' --pane=main:1.3
```

Expected: `module ExCalibur.CampaignRunner is not loaded and could not be found`

**Step 3: Implement**

```elixir
# lib/ex_calibur/campaign_runner.ex
defmodule ExCalibur.CampaignRunner do
  @moduledoc """
  Runs a Campaign's ordered quest steps in sequence.

  Each step's output is formatted as text and prepended to the next step's
  input as additional context. The final step's result is returned.

  Steps are maps: %{"quest_id" => "123", "order" => 1}
  """

  alias ExCalibur.QuestRunner
  alias ExCalibur.Quests

  require Logger

  @doc "Run all steps of a campaign, returning the final step result."
  def run(%{steps: steps} = campaign, input) when steps == [] do
    Logger.info("[CampaignRunner] Campaign #{campaign.id} (#{campaign.name}) has no steps")
    {:ok, %{steps: []}}
  end

  def run(campaign, input) do
    ordered_steps =
      campaign.steps
      |> Enum.sort_by(&Map.get(&1, "order", 0))

    Logger.info(
      "[CampaignRunner] Running campaign #{campaign.id} (#{campaign.name}), #{length(ordered_steps)} step(s)"
    )

    {results, _accumulated_context} =
      Enum.reduce(ordered_steps, {[], input}, fn step, {acc_results, current_input} ->
        quest_id = step["quest_id"]

        case resolve_quest(quest_id) do
          nil ->
            Logger.warning("[CampaignRunner] Quest #{quest_id} not found, skipping step")
            {acc_results ++ [{:error, :quest_not_found}], current_input}

          quest ->
            Logger.info("[CampaignRunner] Running step quest #{quest.id} (#{quest.name})")
            result = QuestRunner.run(quest, current_input)

            # Thread output as extra context for the next step
            next_input =
              case result_to_text(result) do
                "" -> current_input
                text -> "#{current_input}\n\n---\n## Previous Step: #{quest.name}\n#{text}"
              end

            {acc_results ++ [result], next_input}
        end
      end)

    last_result = List.last(results)

    case last_result do
      {:ok, _} = ok -> ok
      _ -> {:ok, %{steps: results}}
    end
  end

  @doc "Format a QuestRunner result as a plain text string for context threading."
  def result_to_text({:ok, %{artifact: %{title: title, body: body}}}) do
    "# #{title}\n#{body}"
  end

  def result_to_text({:ok, %{verdict: verdict, steps: steps}}) do
    summary = Enum.map_join(steps, "\n", fn s -> "- #{s.who}: #{s.verdict}" end)
    "Verdict: #{verdict}\n#{summary}"
  end

  def result_to_text({:ok, %{delivered: true, type: type}}) do
    "Herald delivered (#{type})"
  end

  def result_to_text(_), do: ""

  defp resolve_quest(quest_id) when is_binary(quest_id) do
    case Integer.parse(quest_id) do
      {id, ""} -> Quests.get_quest!(id)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp resolve_quest(quest_id) when is_integer(quest_id) do
    Quests.get_quest!(quest_id)
  rescue
    _ -> nil
  end
end
```

**Step 4: Run tests to verify pass**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur/campaign_runner_test.exs --seed 0' --pane=main:1.3
```

Expected: All 4 tests pass.

**Step 5: Commit**

```bash
git add lib/ex_calibur/campaign_runner.ex test/ex_calibur/campaign_runner_test.exs
git commit -m "feat: add CampaignRunner — sequential quest step execution"
```

---

## Task 3: `QuestDebouncer` — support campaigns

**Files:**
- Modify: `lib/ex_calibur/quest_debouncer.ex`
- Test: `test/ex_calibur/quest_debouncer_test.exs` (create if not exists)

**Background:** The debouncer currently keys state by `quest.id` (an integer). To support campaigns alongside quests without conflict, use tagged tuples as keys: `{:quest, id}` and `{:campaign, id}`. The `handle_info({:fire, key}, state)` handler pattern-matches on the key to dispatch to either `QuestRunner` or `CampaignRunner`.

**Step 1: Write the failing test**

```elixir
# test/ex_calibur/quest_debouncer_test.exs
defmodule ExCalibur.QuestDebouncerTest do
  use ExCalibur.DataCase, async: false

  alias ExCalibur.QuestDebouncer
  alias ExCalibur.Quests

  test "enqueue_campaign/3 accepts a campaign without crashing" do
    {:ok, campaign} =
      Quests.create_campaign(%{
        name: "Debouncer Test Campaign",
        trigger: "source",
        source_ids: ["src-test"]
      })

    items = [%ExCalibur.Sources.SourceItem{content: "test item", source_id: "src-test"}]

    # Should not crash
    assert :ok = QuestDebouncer.enqueue_campaign(campaign, "test-source", items)
  end
end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur/quest_debouncer_test.exs --seed 0' --pane=main:1.3
```

Expected: `function ExCalibur.QuestDebouncer.enqueue_campaign/3 is undefined`

**Step 3: Implement changes to QuestDebouncer**

The diff is:
1. Add `alias ExCalibur.CampaignRunner` at the top
2. Add public `enqueue_campaign/3` function
3. Change state keys from bare `quest.id` to `{:quest, quest.id}` / `{:campaign, campaign.id}`
4. Update `handle_cast` to use the new key format
5. Update `handle_info({:fire, key}, state)` to dispatch based on key type

Full updated file:

```elixir
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
```

**Step 4: Run tests to verify pass**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur/quest_debouncer_test.exs test/ex_calibur/quests_test.exs --seed 0' --pane=main:1.3
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add lib/ex_calibur/quest_debouncer.ex test/ex_calibur/quest_debouncer_test.exs
git commit -m "feat: QuestDebouncer supports campaigns via enqueue_campaign/3"
```

---

## Task 4: `SourceWorker` — also enqueue campaigns

**Files:**
- Modify: `lib/ex_calibur/sources/source_worker.ex`

**Background:** After fetching items, `SourceWorker` currently looks up quests and enqueues them. It needs to also look up campaigns for the source and enqueue each to `QuestDebouncer.enqueue_campaign/3`.

**Step 1: Write the failing test**

There is no clean unit test for SourceWorker (it's a GenServer with I/O). The integration check is: after this change, campaigns fire when their source fires. We verify correctness in Step 4 (run all tests).

Instead, confirm the current test suite is green before we touch this file:

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test --seed 0' --pane=main:1.3
```

Expected: All tests pass.

**Step 2: Implement the change**

In `lib/ex_calibur/sources/source_worker.ex`, modify the `{:ok, items, new_worker_state}` clause and `evaluate_items/3` section:

Current code at line 57-63:
```elixir
{:ok, items, new_worker_state} ->
  maybe_write_to_lore(items, state.source)
  quests = Quests.list_quests_for_source(to_string(state.source.id))
  evaluate_items(items, state.source, quests)
  update_source_state(state.source, new_worker_state)
  timer = Process.send_after(self(), :fetch, state.interval)
  {:noreply, %{state | worker_state: new_worker_state, timer: timer}}
```

Replace with:
```elixir
{:ok, items, new_worker_state} ->
  maybe_write_to_lore(items, state.source)
  quests = Quests.list_quests_for_source(to_string(state.source.id))
  campaigns = Quests.list_campaigns_for_source(to_string(state.source.id))
  evaluate_items(items, state.source, quests)
  enqueue_campaigns(items, state.source, campaigns)
  update_source_state(state.source, new_worker_state)
  timer = Process.send_after(self(), :fetch, state.interval)
  {:noreply, %{state | worker_state: new_worker_state, timer: timer}}
```

Then add the `enqueue_campaigns/3` private function after `evaluate_items/3`:

```elixir
defp enqueue_campaigns(_items, _source, []), do: :ok

defp enqueue_campaigns(items, source, campaigns) do
  label = source.config["label"] || source.source_type
  Logger.info("[SourceWorker] Enqueuing #{length(items)} items from '#{label}' for #{length(campaigns)} campaign(s)")

  Enum.each(campaigns, fn campaign ->
    QuestDebouncer.enqueue_campaign(campaign, label, items)
  end)
end
```

Also add `alias ExCalibur.QuestDebouncer` near the top if not already present (it's already aliased — check line 6).

**Step 3: Run full test suite to verify**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test --seed 0' --pane=main:1.3
```

Expected: All tests pass (no new failures).

**Step 4: Commit**

```bash
git add lib/ex_calibur/sources/source_worker.ex
git commit -m "feat: SourceWorker enqueues campaigns for source-triggered items"
```

---

## Task 5: `ScheduledQuestRunner` — also run due campaigns

**Files:**
- Modify: `lib/ex_calibur/scheduled_quest_runner.ex`

**Background:** The scheduled runner wakes every minute and runs quests whose cron matches. It needs to also check campaigns with `trigger: "scheduled"` and `status: "active"` and run due ones via `CampaignRunner.run/2`.

**Step 1: Verify tests pass before changing**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test --seed 0' --pane=main:1.3
```

**Step 2: Implement the change**

Current `handle_info(:tick, state)`:
```elixir
def handle_info(:tick, state) do
  run_due_quests()
  schedule_tick()
  {:noreply, state}
end
```

Change to:
```elixir
def handle_info(:tick, state) do
  run_due_quests()
  run_due_campaigns()
  schedule_tick()
  {:noreply, state}
end
```

Add `alias ExCalibur.CampaignRunner` near the top, then add the new private functions:

```elixir
defp run_due_campaigns do
  now = DateTime.utc_now()

  Quests.list_campaigns()
  |> Enum.filter(&campaign_scheduled_and_due?(&1, now))
  |> Enum.each(&run_campaign/1)
end

defp campaign_scheduled_and_due?(campaign, now) do
  campaign.trigger == "scheduled" and
    campaign.status == "active" and
    is_binary(campaign.schedule) and
    campaign.schedule != "" and
    cron_matches?(campaign.schedule, now)
end

defp run_campaign(campaign) do
  Logger.info("[ScheduledQuestRunner] Running campaign #{campaign.id} (#{campaign.name})")

  Task.start(fn ->
    case CampaignRunner.run(campaign, "") do
      {:ok, result} ->
        Logger.info("[ScheduledQuestRunner] Campaign #{campaign.id} complete: #{inspect(result)}")

      {:error, reason} ->
        Logger.error("[ScheduledQuestRunner] Campaign #{campaign.id} failed: #{inspect(reason)}")
    end
  end)
end
```

**Step 3: Run full test suite**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test --seed 0' --pane=main:1.3
```

Expected: All tests pass.

**Step 4: Commit**

```bash
git add lib/ex_calibur/scheduled_quest_runner.ex
git commit -m "feat: ScheduledQuestRunner runs due campaigns alongside quests"
```

---

## Task 6: `QuestsLive` — campaigns as primary cards

**Files:**
- Modify: `lib/ex_calibur_web/live/quests_live.ex`

**Background:** QuestsLive is 1814 lines. Currently it shows both quests and campaigns but without strong visual hierarchy. The goal is: campaigns appear as primary cards at the top showing their ordered steps (with quest names); standalone quests (those not referenced by any campaign step) appear in a separate "Standalone Quests" section.

**Step 1: Understand current structure**

Read the top ~80 lines of `lib/ex_calibur_web/live/quests_live.ex` to see mount/assigns:

```bash
tmux-cli send 'grep -n "def mount\|def handle_event\|assigns\|campaigns\|quests" /home/andrew/projects/ex_calibur/lib/ex_calibur_web/live/quests_live.ex | head -60' --pane=main:1.3
```

**Step 2: Gather referenced quest IDs from campaigns**

In `mount/3` (or wherever quests/campaigns are loaded), after loading both:

```elixir
campaigns = Quests.list_campaigns()
quests = Quests.list_quests()

# Quest IDs that are part of any campaign step
campaign_quest_ids =
  campaigns
  |> Enum.flat_map(fn c -> Enum.map(c.steps, &(&1["quest_id"])) end)
  |> MapSet.new()

standalone_quests =
  Enum.reject(quests, fn q -> MapSet.member?(campaign_quest_ids, to_string(q.id)) end)
```

Assign both `campaigns` and `standalone_quests` (replacing the plain `quests` assign, or keep `quests` for editing lookups).

**Step 3: Update template section headers**

In the template (HEEx), find where campaigns and quests are rendered. Add clear section labels:

- Campaigns section: heading "Campaigns" with a subheading explaining they run quests in sequence
- Each campaign card: show name, trigger, schedule/source info, status badge, and an ordered list of step quest names
- Step quest names are resolved by looking up each `quest_id` in the full quests list
- "Standalone Quests" section below with the filtered list

**Step 4: Add Pause/Resume button for campaigns**

In the campaign card, add a toggle button:
- When `campaign.status == "active"`: show "Pause" button → `handle_event("pause_campaign", %{"id" => id}, socket)`
- When `campaign.status == "paused"`: show "Resume" button → `handle_event("resume_campaign", %{"id" => id}, socket)`

Event handlers:
```elixir
def handle_event("pause_campaign", %{"id" => id}, socket) do
  campaign = Quests.get_campaign!(String.to_integer(id))
  {:ok, _} = Quests.update_campaign(campaign, %{status: "paused"})
  {:noreply, assign(socket, campaigns: Quests.list_campaigns())}
end

def handle_event("resume_campaign", %{"id" => id}, socket) do
  campaign = Quests.get_campaign!(String.to_integer(id))
  {:ok, _} = Quests.update_campaign(campaign, %{status: "active"})
  {:noreply, assign(socket, campaigns: Quests.list_campaigns())}
end
```

**Step 5: Run tests**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test --seed 0' --pane=main:1.3
```

Expected: All tests pass. Then visually verify in browser at `/quests`.

**Step 6: Commit**

```bash
git add lib/ex_calibur_web/live/quests_live.ex
git commit -m "feat: QuestsLive shows campaigns as primary cards with standalone quests below"
```

---

## Task 7: Wire BTC quests into campaigns via IEx

**Files:**
- No code changes — DB-only config via `mix run`
- Create: `/tmp/setup_btc_campaigns.exs`

**Background:** The existing BTC prediction quest and retrospective quest should each become a campaign. This makes them pausable and composable. Run this once against the running server's DB.

**Step 1: Create the setup script**

```elixir
# /tmp/setup_btc_campaigns.exs
alias ExCalibur.Quests
alias ExCalibur.Quests.Quest
alias ExCalibur.Repo
import Ecto.Query

# Find quests by name
prediction_quest = Repo.one!(from q in Quest, where: q.name == "BTC Price Prediction")
retro_quest = Repo.one!(from q in Quest, where: q.name == "Prediction Accuracy Retrospective")

# ── Campaign 1: BTC Price Forecast (source-triggered) ─────────────────────
# Inherits source_ids from prediction quest
{:ok, forecast_campaign} =
  Quests.create_campaign(%{
    name: "BTC Price Forecast",
    description: "Generates a 15-minute BTC price prediction when news arrives.",
    trigger: "source",
    source_ids: prediction_quest.source_ids,
    status: "active",
    steps: [%{"quest_id" => to_string(prediction_quest.id), "order" => 1}]
  })

IO.puts("✓ Created campaign: BTC Price Forecast (id=#{forecast_campaign.id})")

# ── Campaign 2: BTC Retrospective (scheduled every 15 min) ────────────────
{:ok, retro_campaign} =
  Quests.create_campaign(%{
    name: "BTC Retrospective",
    description: "Scores the latest prediction against actual price every 15 minutes.",
    trigger: "scheduled",
    schedule: "*/15 * * * *",
    status: "active",
    steps: [%{"quest_id" => to_string(retro_quest.id), "order" => 1}]
  })

IO.puts("✓ Created campaign: BTC Retrospective (id=#{retro_campaign.id})")
IO.puts("Done. Pause the standalone quests if they should only run via campaigns.")
```

**Step 2: Run the script**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix run /tmp/setup_btc_campaigns.exs' --pane=main:1.3
```

Expected:
```
✓ Created campaign: BTC Price Forecast (id=N)
✓ Created campaign: BTC Retrospective (id=M)
```

**Step 3: Verify in browser**

Navigate to `/quests`. Confirm:
- "BTC Price Forecast" and "BTC Retrospective" appear as primary campaign cards
- Each shows its step quest name
- Pause/Resume buttons are present

**Step 4: Optionally pause the standalone quests**

If the quests should only fire via campaigns (to avoid double-running):

```bash
tmux-cli send 'iex -S mix' --pane=main:1.3
```

```elixir
import Ecto.Query
alias ExCalibur.{Quests, Quests.Quest, Repo}

["BTC Price Prediction", "Prediction Accuracy Retrospective"]
|> Enum.each(fn name ->
  q = Repo.one!(from q in Quest, where: q.name == ^name)
  Quests.update_quest(q, %{status: "paused"})
  IO.puts("Paused quest: #{name}")
end)
```

**Step 5: Commit the script for reference**

```bash
git add /tmp/setup_btc_campaigns.exs 2>/dev/null || true
git commit -m "docs: add BTC campaign setup script for reference" --allow-empty
```

---

## Summary

After all tasks:

| Component | Change |
|-----------|--------|
| `Quests.list_campaigns_for_source/1` | New function, mirrors quest equivalent |
| `CampaignRunner` | New module — sequential quest step execution |
| `QuestDebouncer` | State keys tagged `{:quest, id}` / `{:campaign, id}`, new `enqueue_campaign/3` |
| `SourceWorker` | Also fetches + enqueues campaigns on item arrival |
| `ScheduledQuestRunner` | Also runs due campaigns each tick |
| `QuestsLive` | Campaigns as primary cards, standalone quests in secondary section |
| BTC campaigns | DB records wired up via `mix run` script |

Campaigns can be paused to stop them from triggering. Quests continue to work standalone. A single-step campaign is equivalent to the current standalone quest behavior.
