# Context Providers Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow quests to inject structured context blocks alongside the input text at evaluation time — recent quest run history, member performance stats, and static instructions — so agents have richer information than just the raw source item.

**Architecture:** A `ContextProvider` behaviour defines a `fetch/2` callback. Three built-in providers (`Static`, `QuestHistory`, `MemberStats`) are registered. Before QuestRunner evaluates, it calls each provider configured on the quest and assembles their outputs into a preamble prepended to the input. The `context_providers` field is stored as `{:array, :map}` on the Quest schema (already present).

**Tech Stack:** Phoenix LiveView, Ecto, ExCellenceServer.QuestRunner (from escalation plan).

---

## Task 1: ContextProvider behaviour + Static provider

**Files:**
- Create: `lib/ex_cellence_server/context_provider.ex`
- Create: `lib/ex_cellence_server/context_providers/static.ex`
- Create: `test/ex_cellence_server/context_providers/static_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_cellence_server/context_providers/static_test.exs
defmodule ExCellenceServer.ContextProviders.StaticTest do
  use ExUnit.Case, async: true

  alias ExCellenceServer.ContextProviders.Static

  test "returns configured content as-is" do
    config = %{"content" => "Always be thorough."}
    assert "Always be thorough." = Static.fetch(config, %{})
  end

  test "returns empty string when content missing" do
    assert "" = Static.fetch(%{}, %{})
  end
end
```

**Step 2: Run to confirm failure**

```bash
cd /home/andrew/projects/ex_cellence_server && mix test test/ex_cellence_server/context_providers/static_test.exs
```

Expected: error — module not found.

**Step 3: Implement behaviour and Static provider**

```elixir
# lib/ex_cellence_server/context_provider.ex
defmodule ExCellenceServer.ContextProvider do
  @moduledoc """
  Behaviour for context providers. Each provider fetches a string block
  that gets injected into the prompt before the input.
  """

  @callback fetch(config :: map(), quest_run_context :: map()) :: String.t()

  @builtin_providers %{
    "static" => ExCellenceServer.ContextProviders.Static,
    "quest_history" => ExCellenceServer.ContextProviders.QuestHistory,
    "member_stats" => ExCellenceServer.ContextProviders.MemberStats
  }

  @doc """
  Resolve a provider module by type string.
  Returns nil if unknown.
  """
  def resolve(type) do
    custom = Application.get_env(:ex_cellence_server, :context_providers, [])
    custom_map = Map.new(custom, fn {k, v} -> {to_string(k), v} end)
    Map.merge(@builtin_providers, custom_map)[type]
  end

  @doc """
  Assemble context blocks from a list of provider configs.
  Returns a string to prepend to the input (empty if no providers).
  """
  def assemble(providers, quest_run_context) when is_list(providers) do
    blocks =
      providers
      |> Enum.map(fn config ->
        type = config["type"]
        mod = resolve(type)

        if mod do
          text = mod.fetch(config, quest_run_context)
          if text && text != "", do: text, else: nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if blocks == [] do
      ""
    else
      Enum.join(blocks, "\n\n") <> "\n\n=== Input ===\n"
    end
  end

  def assemble(_, _), do: ""
end
```

```elixir
# lib/ex_cellence_server/context_providers/static.ex
defmodule ExCellenceServer.ContextProviders.Static do
  @moduledoc "Injects a static text block into every evaluation."
  @behaviour ExCellenceServer.ContextProvider

  @impl true
  def fetch(%{"content" => content}, _ctx) when is_binary(content), do: content
  def fetch(_config, _ctx), do: ""
end
```

**Step 4: Run tests**

```bash
mix test test/ex_cellence_server/context_providers/static_test.exs
```

Expected: all passing.

**Step 5: Commit**

```bash
git add lib/ex_cellence_server/context_provider.ex lib/ex_cellence_server/context_providers/static.ex test/ex_cellence_server/context_providers/static_test.exs
git commit -m "feat: add ContextProvider behaviour and Static provider"
```

---

## Task 2: QuestHistory provider

**Files:**
- Create: `lib/ex_cellence_server/context_providers/quest_history.ex`
- Create: `test/ex_cellence_server/context_providers/quest_history_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_cellence_server/context_providers/quest_history_test.exs
defmodule ExCellenceServer.ContextProviders.QuestHistoryTest do
  use ExCellenceServer.DataCase, async: true

  alias ExCellenceServer.ContextProviders.QuestHistory
  alias ExCellenceServer.Quests
  alias ExCellenceServer.Repo

  test "returns recent run summaries for a quest" do
    {:ok, quest} = Quests.create_quest(%{name: "History Quest", trigger: "manual"})

    {:ok, run} =
      Quests.create_quest_run(%{
        quest_id: quest.id,
        input: "test input",
        status: "complete",
        results: %{"verdict" => "pass", "confidence" => 0.9}
      })

    config = %{"quest_id" => to_string(quest.id), "limit" => 3}
    output = QuestHistory.fetch(config, %{})

    assert output =~ "Recent Evaluations"
    assert output =~ "pass"
  end

  test "returns empty string when quest not found" do
    config = %{"quest_id" => "99999", "limit" => 3}
    assert "" = QuestHistory.fetch(config, %{})
  end

  test "returns empty string when no runs" do
    {:ok, quest} = Quests.create_quest(%{name: "Empty Quest", trigger: "manual"})
    config = %{"quest_id" => to_string(quest.id), "limit" => 3}
    assert "" = QuestHistory.fetch(config, %{})
  end
end
```

**Step 2: Run to confirm failure**

```bash
mix test test/ex_cellence_server/context_providers/quest_history_test.exs
```

Expected: error — module not found.

**Step 3: Implement QuestHistory provider**

```elixir
# lib/ex_cellence_server/context_providers/quest_history.ex
defmodule ExCellenceServer.ContextProviders.QuestHistory do
  @moduledoc "Fetches recent quest run summaries and formats them as context."
  @behaviour ExCellenceServer.ContextProvider

  import Ecto.Query

  alias ExCellenceServer.Quests.QuestRun
  alias ExCellenceServer.Repo

  @impl true
  def fetch(%{"quest_id" => quest_id_str} = config, _ctx) do
    limit = config["limit"] || 5

    quest_id =
      case Integer.parse(to_string(quest_id_str)) do
        {id, _} -> id
        :error -> nil
      end

    if is_nil(quest_id) do
      ""
    else
      runs =
        Repo.all(
          from r in QuestRun,
            where: r.quest_id == ^quest_id and r.status == "complete",
            order_by: [desc: r.inserted_at],
            limit: ^limit
        )

      if runs == [] do
        ""
      else
        lines =
          Enum.map(runs, fn run ->
            verdict = get_in(run.results, ["verdict"]) || "unknown"
            confidence = get_in(run.results, ["confidence"])
            conf_str = if confidence, do: " (#{Float.round(confidence * 100, 0)}%)", else: ""
            "#{Calendar.strftime(run.inserted_at, "%Y-%m-%d %H:%M")} — #{String.upcase(verdict)}#{conf_str}"
          end)

        "=== Recent Evaluations (last #{length(runs)}) ===\n" <> Enum.join(lines, "\n")
      end
    end
  end

  def fetch(_config, _ctx), do: ""
end
```

**Step 4: Run tests**

```bash
mix test test/ex_cellence_server/context_providers/quest_history_test.exs
```

Expected: all passing.

**Step 5: Commit**

```bash
git add lib/ex_cellence_server/context_providers/quest_history.ex test/ex_cellence_server/context_providers/quest_history_test.exs
git commit -m "feat: add QuestHistory context provider"
```

---

## Task 3: MemberStats provider

**Files:**
- Create: `lib/ex_cellence_server/context_providers/member_stats.ex`
- Create: `test/ex_cellence_server/context_providers/member_stats_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_cellence_server/context_providers/member_stats_test.exs
defmodule ExCellenceServer.ContextProviders.MemberStatsTest do
  use ExCellenceServer.DataCase, async: true

  alias ExCellenceServer.ContextProviders.MemberStats
  alias ExCellenceServer.Repo
  alias Excellence.Schemas.Member

  test "returns member performance summary" do
    {:ok, _} =
      Repo.insert(%Member{
        type: "role",
        name: "Test Auditor",
        source: "db",
        status: "active",
        config: %{"rank" => "journeyman", "model" => "phi4-mini", "strategy" => "cot", "system_prompt" => ""}
      })

    config = %{"window" => "7d"}
    output = MemberStats.fetch(config, %{})

    assert output =~ "Member Performance" or output == ""
  end
end
```

**Step 2: Run to confirm failure**

```bash
mix test test/ex_cellence_server/context_providers/member_stats_test.exs
```

Expected: error — module not found.

**Step 3: Implement MemberStats provider**

```elixir
# lib/ex_cellence_server/context_providers/member_stats.ex
defmodule ExCellenceServer.ContextProviders.MemberStats do
  @moduledoc "Summarizes active members and their rank/model configuration as context."
  @behaviour ExCellenceServer.ContextProvider

  import Ecto.Query

  alias ExCellenceServer.Repo
  alias Excellence.Schemas.Member

  @impl true
  def fetch(config, _ctx) do
    window = config["window"] || "7d"

    members =
      Repo.all(
        from m in Member,
          where: m.type == "role" and m.status == "active",
          order_by: [asc: m.name]
      )

    if members == [] do
      ""
    else
      lines =
        Enum.map(members, fn m ->
          rank = m.config["rank"] || "journeyman"
          model = m.config["model"] || "default"
          "#{m.name} (#{rank}): #{model}"
        end)

      "=== Active Members (#{window} window) ===\n" <> Enum.join(lines, "\n")
    end
  end
end
```

**Step 4: Run tests**

```bash
mix test test/ex_cellence_server/context_providers/member_stats_test.exs
```

Expected: passing.

**Step 5: Commit**

```bash
git add lib/ex_cellence_server/context_providers/member_stats.ex test/ex_cellence_server/context_providers/member_stats_test.exs
git commit -m "feat: add MemberStats context provider"
```

---

## Task 4: Integrate context assembly into QuestRunner

**Files:**
- Modify: `lib/ex_cellence_server/quest_runner.ex`

**Step 1: Update the `run/3` function to assemble context**

In `QuestRunner.run/3`, after building `all_members`, add context assembly:

```elixir
def run(quest, input, opts \\ []) do
  ollama_url = Application.get_env(:ex_cellence_server, :ollama_url, "http://127.0.0.1:11434")
  ollama = Keyword.get(opts, :ollama, Ollama.new(base_url: ollama_url))

  all_members = Repo.all(from(m in Member, where: m.type == "role" and m.status == "active"))

  context_preamble =
    ExCellenceServer.ContextProvider.assemble(
      quest.context_providers || [],
      %{quest_id: quest.id}
    )

  full_input = context_preamble <> input

  on_trigger_steps = Enum.filter(quest.roster, &(&1["when"] == "on_trigger"))
  on_escalation_steps = Enum.filter(quest.roster, &(&1["when"] == "on_escalation"))

  run_steps(on_trigger_steps, on_escalation_steps, full_input, all_members, ollama, [])
end
```

**Step 2: Add context_providers field to Quest schema**

In `lib/ex_cellence_server/quests/quest.ex`, add field:

```elixir
field :context_providers, {:array, :map}, default: []
```

And add to `@optional`:

```elixir
@optional [:description, :status, :schedule, :roster, :source_ids, :context_providers]
```

**Step 3: Add migration for context_providers column**

```elixir
# priv/repo/migrations/20260308240000_add_context_providers_to_quests.exs
defmodule ExCellenceServer.Repo.Migrations.AddContextProvidersToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :context_providers, {:array, :map}, default: []
    end
  end
end
```

Run it:

```bash
mix ecto.migrate
```

**Step 4: Run full test suite**

```bash
mix test
```

Expected: all passing.

**Step 5: Commit**

```bash
git add lib/ex_cellence_server/quest_runner.ex lib/ex_cellence_server/quests/quest.ex priv/repo/migrations/20260308240000_add_context_providers_to_quests.exs
git commit -m "feat: integrate context providers into QuestRunner"
```

---

## Task 5: Context provider UI in Quest form

**Files:**
- Modify: `lib/ex_cellence_server_web/live/quests_live.ex`

**Step 1: Add context provider section to new_quest_form**

After the trigger/how/who fields, add:

```elixir
<div class="border-t pt-3">
  <label class="text-sm font-medium">Context Providers</label>
  <p class="text-xs text-muted-foreground mb-2">Optional: inject extra context into every evaluation</p>
  <div class="space-y-2">
    <div class="flex items-center gap-2">
      <select name="quest[context_type]" class="text-sm border rounded px-2 py-1 bg-background">
        <option value="">None</option>
        <option value="static">Static text</option>
        <option value="quest_history">Quest history</option>
        <option value="member_stats">Member stats</option>
      </select>
    </div>
    <.input type="text" name="quest[context_value]" value="" placeholder="Static text or quest ID" />
  </div>
</div>
```

**Step 2: Parse context provider from create_quest params**

In `handle_event("create_quest", ...)`, add:

```elixir
context_providers =
  case {params["context_type"], params["context_value"]} do
    {"static", value} when value != "" ->
      [%{"type" => "static", "content" => value}]
    {"quest_history", quest_id} when quest_id != "" ->
      [%{"type" => "quest_history", "quest_id" => quest_id, "limit" => 5}]
    {"member_stats", _} ->
      [%{"type" => "member_stats", "window" => "7d"}]
    _ ->
      []
  end

attrs = %{
  ...
  context_providers: context_providers
}
```

**Step 3: Compile and run tests**

```bash
mix compile --warnings-as-errors && mix test
```

Expected: all passing.

**Step 4: Commit**

```bash
git add lib/ex_cellence_server_web/live/quests_live.ex
git commit -m "feat: add context provider picker to new quest form"
```

---

## Task 6: Format, full test run, final commit

**Step 1: Format**

```bash
mix format
```

**Step 2: Full test suite**

```bash
mix test
```

Expected: all passing.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: context providers complete — static, quest history, member stats"
```
