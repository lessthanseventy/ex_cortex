# ExCortex Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Rename ExCalibur → ExCortex with brain/consciousness vocabulary, add OpenViking-style tiered memory, dual web+TUI frontend, and Burrito standalone binary.

**Architecture:** Single Elixir app (`ex_cortex`). In-place rename of the existing repo to preserve git history. One big DB migration renames all tables and adds memory system tables. Core business logic in `ExCortex.*`, web frontend in `ExCortexWeb.*` with WebTUI styling, terminal frontend in `ExCortexTUI.*` with Owl. Burrito wraps the release as a standalone `./ex_cortex` binary.

**Tech Stack:** Phoenix 1.8, Ecto, Oban, Owl (terminal UI), WebTUI CSS (or hand-rolled), Burrito, Tokyo Night theme.

**Design doc:** `docs/plans/2026-03-14-ex-cortex-redesign.md`

---

## Phase 1: Foundation

### Task 0: Rename Mix Project

Rename the Elixir application from `:ex_calibur` to `:ex_cortex`. This touches mix.exs, config files, and the top-level module names.

**Files:**
- Modify: `mix.exs`
- Modify: `config/config.exs`
- Modify: `config/dev.exs`
- Modify: `config/test.exs`
- Modify: `config/prod.exs`
- Modify: `config/runtime.exs`

**Step 1: Update mix.exs**

Change app name, module name, and all internal references:

```elixir
# mix.exs
def project do
  [
    app: :ex_cortex,
    version: "1.0.0",
    # ...
    compilers: Mix.compilers(),
    aliases: aliases(),
    deps: deps()
  ]
end

def application do
  [
    mod: {ExCortex.Application, []},
    extra_applications: [:logger, :runtime_tools]
  ]
end
```

**Step 2: Update all config files**

Replace every `ExCalibur` → `ExCortex`, `ex_calibur` → `ex_cortex`:
- `config/config.exs`: endpoint, oban, repos, pubsub
- `config/dev.exs`: database name → `ex_cortex_dev`, endpoint
- `config/test.exs`: database name → `ex_cortex_test`, endpoint
- `config/prod.exs`: endpoint, database
- `config/runtime.exs`: endpoint, repo, database URL

**Step 3: Rename top-level directories**

```bash
mv lib/ex_calibur lib/ex_cortex
mv lib/ex_calibur_web lib/ex_cortex_web
mv lib/ex_calibur_web.ex lib/ex_cortex_web.ex
mv lib/ex_calibur.ex lib/ex_cortex.ex
mv test/ex_calibur test/ex_cortex
mv test/ex_calibur_web test/ex_cortex_web
```

**Step 4: Global find-and-replace module names**

In all `.ex`, `.exs`, `.heex`, `.js` files:
- `ExCalibur` → `ExCortex` (module names)
- `ExCaliburWeb` → `ExCortexWeb` (web module names)
- `ex_calibur` → `ex_cortex` (atoms, strings, paths)
- `ExCaliburUI` → `ExCortexWeb.Components` (absorbed UI components)

**Step 5: Compile and verify**

```bash
mix deps.get && mix compile --warnings-as-errors
```

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename ExCalibur → ExCortex"
```

---

### Task 1: Database Migration — Rename Tables

Write the big migration that renames all tables to brain vocabulary.

**Files:**
- Create: `priv/repo/migrations/XXXXXXXX_rename_to_cortex.exs`

**Step 1: Write the migration**

```elixir
defmodule ExCortex.Repo.Migrations.RenameToCortex do
  use Ecto.Migration

  def change do
    # Rename existing tables
    rename table(:excellence_resources), to: table(:neurons)
    rename table(:excellence_quests), to: table(:thoughts)
    rename table(:excellence_quest_runs), to: table(:thought_runs)
    rename table(:excellence_step_runs), to: table(:impulses)
    rename table(:lore_entries), to: table(:engrams)
    rename table(:lodge_cards), to: table(:signals)
    rename table(:guild_charters), to: table(:clusters)
    rename table(:member_trust_scores), to: table(:neuron_trust_scores)

    # Add memory tier fields to engrams
    alter table(:engrams) do
      add :impression, :text           # L0 (~100 tokens)
      add :recall, :text               # L1 (~1k tokens)
      add :category, :string, default: "semantic"
      add :cluster_name, :string
      add :thought_run_id, references(:thought_runs, on_delete: :nilify_all)
    end

    # Create recall_paths table
    create table(:recall_paths) do
      add :thought_run_id, references(:thought_runs, on_delete: :delete_all), null: false
      add :engram_id, references(:engrams, on_delete: :delete_all), null: false
      add :reason, :text
      add :relevance_score, :float
      add :tier_accessed, :string
      add :step, :integer
      timestamps()
    end

    # Create senses table (sources were mostly in-memory)
    create table(:senses) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :config, :map, default: %{}
      add :cluster_id, references(:clusters, on_delete: :nilify_all)
      add :status, :string, default: "active"
      timestamps()
    end

    # Indexes
    create index(:engrams, [:category])
    create index(:engrams, [:cluster_name])
    create index(:engrams, [:tags], using: "GIN")
    create index(:recall_paths, [:thought_run_id])
    create index(:recall_paths, [:engram_id])
    create index(:senses, [:type])
    create index(:senses, [:cluster_id])
  end
end
```

**Step 2: Run migration**

```bash
mix ecto.migrate
```

**Step 3: Commit**

```bash
git add priv/repo/migrations/
git commit -m "feat: rename DB tables to cortex vocabulary, add memory system tables"
```

---

### Task 2: Rename Schemas & Contexts

Rename all Ecto schemas and context modules to new vocabulary. This is the bulk rename — every schema gets a new module name and table reference.

**Files (rename/modify all):**
- `lib/ex_cortex/clusters/cluster.ex` ← was `guild_charters/guild_charter.ex`
- `lib/ex_cortex/clusters/registry.ex` ← was `guild_charters.ex` (context)
- `lib/ex_cortex/neurons/neuron.ex` ← was `schemas/member.ex`
- `lib/ex_cortex/neurons/builtin.ex` ← was `members/builtin_member.ex`
- `lib/ex_cortex/neurons/trust.ex` ← was `trust/member_trust_score.ex`
- `lib/ex_cortex/thoughts/thought.ex` ← was `quests/quest.ex`
- `lib/ex_cortex/thoughts/run.ex` ← was `quests/quest_run.ex`
- `lib/ex_cortex/thoughts/impulse.ex` ← was `quests/step_run.ex`
- `lib/ex_cortex/thoughts/runner.ex` ← was `quest_runner.ex` + `step_runner.ex`
- `lib/ex_cortex/thoughts/scheduler.ex` ← was `scheduled_quest_runner.ex`
- `lib/ex_cortex/thoughts/throttle.ex` ← was `quest_throttle.ex`
- `lib/ex_cortex/memory/engram.ex` ← was `lore/lore_entry.ex`
- `lib/ex_cortex/memory/signal.ex` ← was `lodge/card.ex`
- `lib/ex_cortex/senses/sense.ex` ← NEW schema
- `lib/ex_cortex/pathways/*.ex` ← was `charters/*.ex`
- `lib/ex_cortex/neuroplasticity/` ← was `self_improvement/`

**Step 1: Write the Engram schema (new version of LoreEntry)**

```elixir
defmodule ExCortex.Memory.Engram do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "engrams" do
    field :title, :string
    field :body, :string, default: ""
    field :impression, :string         # L0
    field :recall, :string             # L1
    field :tags, {:array, :string}, default: []
    field :importance, :integer
    field :source, :string, default: "thought"
    field :category, :string, default: "semantic"
    field :cluster_name, :string
    field :thought_run_id, :integer
    timestamps()
  end

  @required [:title]
  @optional [:body, :impression, :recall, :tags, :importance, :source,
             :category, :cluster_name, :thought_run_id]

  def changeset(engram, attrs) do
    engram
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:source, ~w(thought manual sense extraction))
    |> validate_inclusion(:category, ~w(episodic semantic procedural))
    |> validate_number(:importance, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
  end
end
```

**Step 2: Write the Sense schema (new)**

```elixir
defmodule ExCortex.Senses.Sense do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "senses" do
    field :name, :string
    field :type, :string
    field :config, :map, default: %{}
    field :cluster_id, :integer
    field :status, :string, default: "active"
    timestamps()
  end

  @required [:name, :type]
  @optional [:config, :cluster_id, :status]

  def changeset(sense, attrs) do
    sense
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:type, ~w(git directory feed webhook url websocket))
    |> validate_inclusion(:status, ~w(active paused stopped))
  end
end
```

**Step 3: Write RecallPath schema (new)**

```elixir
defmodule ExCortex.Memory.RecallPath do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "recall_paths" do
    field :thought_run_id, :integer
    field :engram_id, :integer
    field :reason, :string
    field :relevance_score, :float
    field :tier_accessed, :string
    field :step, :integer
    timestamps()
  end

  def changeset(path, attrs) do
    path
    |> cast(attrs, [:thought_run_id, :engram_id, :reason, :relevance_score, :tier_accessed, :step])
    |> validate_required([:thought_run_id, :engram_id])
    |> validate_inclusion(:tier_accessed, ~w(L0 L1 L2))
  end
end
```

**Step 4: Rename all remaining schemas**

Mechanical rename of every schema module — update `defmodule`, table name in `schema`, and all references. For each file:
1. Rename the file to new path
2. Update `defmodule` to new module name
3. Update `schema` table name
4. Find all callers and update references

Key renames:
- `ExCalibur.GuildCharters.GuildCharter` → `ExCortex.Clusters.Cluster` (table: `clusters`)
- `ExCalibur.Schemas.Member` → `ExCortex.Neurons.Neuron` (table: `neurons`)
- `ExCalibur.Quests.Quest` → `ExCortex.Thoughts.Thought` (table: `thoughts`)
- `ExCalibur.Quests.QuestRun` → `ExCortex.Thoughts.Run` (table: `thought_runs`)
- `ExCalibur.Quests.StepRun` → `ExCortex.Thoughts.Impulse` (table: `impulses`)
- `ExCalibur.Lodge.Card` → `ExCortex.Memory.Signal` (table: `signals`)
- `ExCalibur.Trust.MemberTrustScore` → `ExCortex.Neurons.Trust` (table: `neuron_trust_scores`)
- `ExCalibur.Members.BuiltinMember` → `ExCortex.Neurons.Builtin`

**Step 5: Rename context modules**

- `ExCalibur.Quests` → `ExCortex.Thoughts` (context functions)
- `ExCalibur.GuildCharters` → `ExCortex.Clusters`
- `ExCalibur.Lore` → `ExCortex.Memory` (if exists as context)
- `ExCalibur.Lodge` → `ExCortex.Memory.Signals`

**Step 6: Rename charter modules to pathways**

Move `lib/ex_cortex/charters/*.ex` → `lib/ex_cortex/pathways/*.ex` and rename modules:
- `ExCalibur.Charters.PlatformGuild` → `ExCortex.Pathways.Platform`
- `ExCalibur.Charters.DevTeam` → `ExCortex.Pathways.DevTeam`
- etc. for all ~20 charter modules

**Step 7: Rename self-improvement to neuroplasticity**

- `ExCalibur.SelfImprovement.*` → `ExCortex.Neuroplasticity.*`
- `ExCalibur.LearningLoop` → `ExCortex.Neuroplasticity.Loop`

**Step 8: Rename agent infrastructure**

- `ExCalibur.Agent.Registry` → `ExCortex.Core.Registry`
- `ExCalibur.Agent.Orchestrator` → `ExCortex.Core.Orchestrator`
- `ExCalibur.Agent.Verdict` → `ExCortex.Core.Verdict`
- `ExCalibur.Agent.Consensus` → `ExCortex.Core.Consensus`
- `ExCalibur.Agent.LLM` → `ExCortex.Core.LLM`
- `ExCalibur.Agent.Role` → `ExCortex.Core.Role`
- `ExCalibur.Agent.Actions` → `ExCortex.Core.Actions`
- `ExCalibur.Evaluator` → `ExCortex.Core.Evaluator`

**Step 9: Rename tools**

- `ExCalibur.Tools.QueryLore` → `ExCortex.Tools.QueryMemory`
- `ExCalibur.Tools.RunQuest` → `ExCortex.Tools.RunThought`
- All other tools: `ExCalibur.Tools.*` → `ExCortex.Tools.*`

**Step 10: Rename herald modules to impulses**

- `ExCalibur.Heralds.*` → `ExCortex.Impulses.*`
- `ExCalibur.Heralds.Herald` → `ExCortex.Impulses.Impulse`

**Step 11: Rename source modules to senses**

- `ExCalibur.Sources.*` → `ExCortex.Senses.*`
- `ExCalibur.Sources.SourceSupervisor` → `ExCortex.Senses.Supervisor`
- `ExCalibur.Sources.Book` → `ExCortex.Senses.Reflex`
- `ExCalibur.Sources.Behaviour` → `ExCortex.Senses.Behaviour`

**Step 12: Compile and fix**

```bash
mix compile --warnings-as-errors 2>&1 | head -100
```

Fix any remaining references. Iterate until clean compile.

**Step 13: Run tests**

```bash
mix test
```

Fix failures from renamed modules.

**Step 14: Commit**

```bash
git add -A
git commit -m "refactor: rename all schemas and contexts to cortex vocabulary"
```

---

### Task 3: Update Router & Application

**Files:**
- Modify: `lib/ex_cortex_web/router.ex`
- Modify: `lib/ex_cortex/application.ex`

**Step 1: Rewrite router with new routes**

```elixir
scope "/", ExCortexWeb do
  pipe_through :browser

  live_session :default, on_mount: [{ExCortexWeb.Hooks, :assign_lobe}] do
    live "/", CortexLive
    live "/cortex", CortexLive
    live "/neurons", NeuronsLive
    live "/thoughts", ThoughtsLive
    live "/memory", MemoryLive
    live "/senses", SensesLive
    live "/instinct", InstinctLive
    live "/guide", GuideLive
  end
end

scope "/api", ExCortexWeb do
  pipe_through :api
  post "/webhooks/:sense_id", WebhookController, :ingest
end
```

**Step 2: Update application.ex supervision tree**

Rename all children references:
- `ExCortex.Repo`
- `ExCortex.Core.Registry`
- `{Oban, ...}`
- `{Phoenix.PubSub, name: ExCortex.PubSub}`
- `ExCortex.Senses.Supervisor`
- `ExCortex.Thoughts.Scheduler`
- `ExCortex.Memory.TriggerRunner` (was LoreTriggerRunner)
- `ExCortex.Memory.SignalTriggerRunner` (was LodgeTriggerRunner)
- `ExCortexWeb.Endpoint`

**Step 3: Compile and verify**

```bash
mix compile --warnings-as-errors
```

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: update router and supervision tree for cortex vocabulary"
```

---

## Phase 2: Memory System

### Task 4: Memory Context Module

Write the `ExCortex.Memory` context with tiered query support.

**Files:**
- Create: `lib/ex_cortex/memory.ex`
- Modify: `lib/ex_cortex/tools/query_memory.ex`

**Step 1: Write failing test for tiered query**

```elixir
# test/ex_cortex/memory_test.exs
defmodule ExCortex.MemoryTest do
  use ExCortex.DataCase

  alias ExCortex.Memory

  describe "query/2 with tiered loading" do
    setup do
      {:ok, engram} = Memory.create_engram(%{
        title: "API auth patterns",
        body: "Full detailed content about OAuth2, JWT, and API keys...",
        impression: "API authentication guide covering OAuth 2.0, JWT, API keys",
        recall: "# Auth Guide\n## OAuth 2.0\nRecommended for user-facing...\n## JWT\nFor service-to-service...",
        category: "semantic",
        tags: ["api", "auth"],
        importance: 4
      })
      %{engram: engram}
    end

    test "returns L0 impressions for initial search", %{engram: engram} do
      results = Memory.query("authentication", tier: :L0)
      assert length(results) > 0
      result = hd(results)
      assert result.id == engram.id
      assert result.impression != nil
      assert result.body == nil  # L2 not loaded
    end

    test "loads L1 recall for selected engrams", %{engram: engram} do
      result = Memory.load_recall(engram.id)
      assert result.recall =~ "OAuth 2.0"
      assert result.body == nil  # still no L2
    end

    test "loads L2 deep content on demand", %{engram: engram} do
      result = Memory.load_deep(engram.id)
      assert result.body =~ "Full detailed content"
    end
  end

  describe "create_engram/1" do
    test "creates with category" do
      {:ok, engram} = Memory.create_engram(%{
        title: "Test event",
        body: "Something happened",
        category: "episodic",
        source: "thought"
      })
      assert engram.category == "episodic"
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/ex_cortex/memory_test.exs
```

**Step 3: Implement Memory context**

```elixir
defmodule ExCortex.Memory do
  @moduledoc "Context for engrams (memories) with tiered loading."

  import Ecto.Query

  alias ExCortex.Memory.Engram
  alias ExCortex.Memory.RecallPath
  alias ExCortex.Repo

  # --- CRUD ---

  def create_engram(attrs) do
    %Engram{}
    |> Engram.changeset(attrs)
    |> Repo.insert()
  end

  def list_engrams(opts \\ []) do
    Engram
    |> maybe_filter_category(opts[:category])
    |> maybe_filter_tags(opts[:tags])
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  # --- Tiered Query ---

  def query(search_term, opts \\ []) do
    tier = Keyword.get(opts, :tier, :L0)
    limit = Keyword.get(opts, :limit, 20)

    select_fields = case tier do
      :L0 -> [:id, :title, :impression, :tags, :importance, :category, :inserted_at]
      :L1 -> [:id, :title, :impression, :recall, :tags, :importance, :category, :inserted_at]
      :L2 -> [:id, :title, :impression, :recall, :body, :tags, :importance, :category, :inserted_at]
    end

    from(e in Engram,
      where: ilike(e.title, ^"%#{search_term}%")
         or ilike(e.impression, ^"%#{search_term}%")
         or ^search_term in e.tags,
      select: struct(e, ^select_fields),
      order_by: [desc: e.importance, desc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def load_recall(engram_id) do
    from(e in Engram,
      where: e.id == ^engram_id,
      select: struct(e, [:id, :title, :impression, :recall, :tags, :importance, :category])
    )
    |> Repo.one()
  end

  def load_deep(engram_id) do
    Repo.get(Engram, engram_id)
  end

  # --- Recall Paths ---

  def log_recall(attrs) do
    %RecallPath{}
    |> RecallPath.changeset(attrs)
    |> Repo.insert()
  end

  def recall_paths_for_run(thought_run_id) do
    from(rp in RecallPath,
      where: rp.thought_run_id == ^thought_run_id,
      join: e in Engram, on: e.id == rp.engram_id,
      select: %{recall_path: rp, engram_title: e.title},
      order_by: [asc: rp.step, asc: rp.inserted_at]
    )
    |> Repo.all()
  end

  # --- Filters ---

  defp maybe_filter_category(query, nil), do: query
  defp maybe_filter_category(query, cat), do: where(query, [e], e.category == ^cat)

  defp maybe_filter_tags(query, nil), do: query
  defp maybe_filter_tags(query, tags), do: where(query, [e], fragment("? && ?", e.tags, ^tags))
end
```

**Step 4: Run tests**

```bash
mix test test/ex_cortex/memory_test.exs
```

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Memory context with tiered query (L0/L1/L2)"
```

---

### Task 5: Memory Extractor

Post-thought hook that auto-creates engrams from completed thought runs.

**Files:**
- Create: `lib/ex_cortex/memory/extractor.ex`
- Create: `test/ex_cortex/memory/extractor_test.exs`

**Step 1: Write failing test**

```elixir
defmodule ExCortex.Memory.ExtractorTest do
  use ExCortex.DataCase

  alias ExCortex.Memory
  alias ExCortex.Memory.Extractor

  describe "extract/1" do
    test "creates episodic engram from thought run" do
      thought_run = %{
        id: 1,
        thought_name: "SI Analyst Sweep",
        cluster_name: "Dev Team",
        status: "complete",
        results: %{
          "summary" => "Found 2 credo issues, filed GH issues #89 #90"
        },
        impulses: [
          %{step: 1, input: "scan codebase", results: %{"output" => "2 issues"}},
          %{step: 2, input: "file issues", results: %{"output" => "filed #89 #90"}}
        ]
      }

      {:ok, engrams} = Extractor.extract(thought_run)

      episodic = Enum.find(engrams, &(&1.category == "episodic"))
      assert episodic != nil
      assert episodic.title =~ "SI Analyst Sweep"
      assert episodic.source == "extraction"
      assert episodic.thought_run_id == 1
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/ex_cortex/memory/extractor_test.exs
```

**Step 3: Implement Extractor**

```elixir
defmodule ExCortex.Memory.Extractor do
  @moduledoc "Extracts structured engrams from completed thought runs."

  alias ExCortex.LLM
  alias ExCortex.Memory

  def extract(thought_run) do
    engrams = []

    # Always create episodic (what happened)
    {:ok, episodic} = create_episodic(thought_run)
    engrams = [episodic | engrams]

    # Ask LLM about semantic patterns (optional, async-safe)
    case maybe_create_semantic(thought_run) do
      {:ok, semantic} -> engrams = [semantic | engrams]
      _ -> :ok
    end

    # Ask LLM about procedural knowledge (optional, async-safe)
    case maybe_create_procedural(thought_run) do
      {:ok, procedural} -> engrams = [procedural | engrams]
      _ -> :ok
    end

    {:ok, engrams}
  end

  defp create_episodic(thought_run) do
    summary = summarize_run(thought_run)

    Memory.create_engram(%{
      title: "#{thought_run.thought_name} ##{thought_run.id}",
      body: summary,
      category: "episodic",
      source: "extraction",
      cluster_name: thought_run.cluster_name,
      thought_run_id: thought_run.id,
      importance: 2,
      tags: ["thought-run", thought_run.thought_name |> String.downcase() |> String.replace(" ", "-")]
    })
  end

  defp maybe_create_semantic(thought_run) do
    prompt = """
    Analyze this thought run output. If any new facts or patterns were discovered,
    return a JSON object with {"title": "...", "body": "..."}. If nothing novel, return null.

    Run: #{thought_run.thought_name}
    Results: #{inspect(thought_run.results)}
    """

    case LLM.chat(prompt, model: fastest_model()) do
      {:ok, %{"title" => title, "body" => body}} ->
        Memory.create_engram(%{
          title: title,
          body: body,
          category: "semantic",
          source: "extraction",
          cluster_name: thought_run.cluster_name,
          thought_run_id: thought_run.id,
          importance: 3
        })
      _ -> :skip
    end
  end

  defp maybe_create_procedural(thought_run) do
    prompt = """
    Analyze this thought run. If a reusable procedure or skill was demonstrated,
    return a JSON object with {"title": "How to ...", "body": "..."}. If not, return null.

    Run: #{thought_run.thought_name}
    Steps: #{inspect(thought_run.impulses)}
    """

    case LLM.chat(prompt, model: fastest_model()) do
      {:ok, %{"title" => title, "body" => body}} ->
        Memory.create_engram(%{
          title: title,
          body: body,
          category: "procedural",
          source: "extraction",
          cluster_name: thought_run.cluster_name,
          thought_run_id: thought_run.id,
          importance: 3
        })
      _ -> :skip
    end
  end

  defp summarize_run(thought_run) do
    impulse_summary =
      thought_run.impulses
      |> Enum.map(fn i -> "Step #{i.step}: #{inspect(i.results)}" end)
      |> Enum.join("\n")

    "Thought: #{thought_run.thought_name}\nStatus: #{thought_run.status}\n\n#{impulse_summary}"
  end

  defp fastest_model, do: "ministral-3:3b"
end
```

**Step 4: Run tests**

```bash
mix test test/ex_cortex/memory/extractor_test.exs
```

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Memory.Extractor for post-thought engram extraction"
```

---

### Task 6: Tier Generator

Async worker that generates L0/L1 summaries for engrams.

**Files:**
- Create: `lib/ex_cortex/memory/tier_generator.ex`
- Create: `test/ex_cortex/memory/tier_generator_test.exs`

**Step 1: Write failing test**

```elixir
defmodule ExCortex.Memory.TierGeneratorTest do
  use ExCortex.DataCase

  alias ExCortex.Memory
  alias ExCortex.Memory.TierGenerator

  describe "generate/1" do
    test "generates L0 and L1 for an engram with only L2 body" do
      {:ok, engram} = Memory.create_engram(%{
        title: "Deploy runbook",
        body: "# Deploy Runbook\n\n## Prerequisites\nEnsure Docker is running...\n\n## Steps\n1. Pull latest...\n2. Run migrations...\n3. Start services...\n\n## Rollback\nIf anything fails...",
        category: "procedural"
      })

      assert engram.impression == nil
      assert engram.recall == nil

      {:ok, updated} = TierGenerator.generate(engram)

      assert updated.impression != nil
      assert String.length(updated.impression) < 500  # ~100 tokens
      assert updated.recall != nil
      assert String.length(updated.recall) < 5000     # ~1k tokens
    end
  end
end
```

**Step 2: Implement TierGenerator**

```elixir
defmodule ExCortex.Memory.TierGenerator do
  @moduledoc "Generates L0 (impression) and L1 (recall) summaries for engrams."

  alias ExCortex.LLM
  alias ExCortex.Memory.Engram
  alias ExCortex.Repo

  def generate(%Engram{body: nil}), do: {:error, :no_body}
  def generate(%Engram{body: ""}), do: {:error, :no_body}

  def generate(%Engram{} = engram) do
    with {:ok, impression} <- generate_impression(engram),
         {:ok, recall} <- generate_recall(engram) do
      engram
      |> Engram.changeset(%{impression: impression, recall: recall})
      |> Repo.update()
    end
  end

  def generate_async(%Engram{} = engram) do
    Task.Supervisor.start_child(ExCortex.AsyncTaskSupervisor, fn ->
      generate(engram)
    end)
  end

  defp generate_impression(engram) do
    prompt = """
    Summarize the following in ONE sentence, max 100 tokens.
    Capture the essence — what is this about and why does it matter?

    Title: #{engram.title}
    Content: #{engram.body}
    """

    case LLM.chat(prompt, model: "ministral-3:3b") do
      {:ok, text} when is_binary(text) -> {:ok, String.trim(text)}
      error -> {:error, error}
    end
  end

  defp generate_recall(engram) do
    prompt = """
    Create a structured summary of the following content in ~500-1000 tokens.
    Include section headings and key points. End with pointers to what detailed
    information is available if someone needs to go deeper.

    Title: #{engram.title}
    Content: #{engram.body}
    """

    case LLM.chat(prompt, model: "ministral-3:3b") do
      {:ok, text} when is_binary(text) -> {:ok, String.trim(text)}
      error -> {:error, error}
    end
  end
end
```

**Step 3: Run tests**

```bash
mix test test/ex_cortex/memory/tier_generator_test.exs
```

**Step 4: Wire into Extractor**

Add `TierGenerator.generate_async(engram)` call after every `Memory.create_engram` in the Extractor.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add TierGenerator for L0/L1 engram summaries"
```

---

### Task 7: Wire Memory Extraction into Thought Runner

Hook the extractor into the thought run completion path.

**Files:**
- Modify: `lib/ex_cortex/thoughts/runner.ex` (was quest_runner.ex)

**Step 1: Find the thought run completion point**

Look for where quest runs are marked as complete — likely in `QuestRunner` or the Oban worker. Add a post-completion hook.

**Step 2: Add extraction hook**

```elixir
# In the thought runner, after a run completes:
defp on_thought_complete(thought_run) do
  Task.Supervisor.start_child(ExCortex.AsyncTaskSupervisor, fn ->
    ExCortex.Memory.Extractor.extract(thought_run)
  end)
end
```

**Step 3: Wire query_memory tool to use tiered recall**

Update `ExCortex.Tools.QueryMemory` to use the new `Memory.query/2` with tiers and log recall paths.

**Step 4: Run tests**

```bash
mix test
```

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: wire memory extraction into thought runner, update query_memory tool"
```

---

## Phase 3: Web Frontend (WebTUI)

### Task 8: CSS & Layout Foundation

Replace SaladUI styles with Tokyo Night + WebTUI aesthetic. Set up the app shell layout.

**Files:**
- Modify: `assets/css/app.css`
- Create: `assets/css/tui.css` (hand-rolled TUI styles if WebTUI doesn't fit)
- Modify: `lib/ex_cortex_web/layouts/app.html.heex`
- Modify: `assets/js/app.js`
- Modify: `mix.exs` (remove salad_ui dep)

**Step 1: Install WebTUI (try it first)**

```bash
cd assets && npm install @webtui/css @webtui/theme-nord && cd ..
```

If WebTUI plays nice with Phoenix asset pipeline, import it. If not, hand-roll the CSS (it's ~150 lines for the box-drawing + monospace + palette).

**Step 2: Write the base CSS**

```css
/* assets/css/app.css */
@import "tailwindcss";

:root {
  /* Tokyo Night base */
  --bg: #1a1b26;
  --bg-surface: #1f2335;
  --bg-highlight: #292e42;
  --fg: #a9b1d6;
  --fg-dim: #565f89;

  /* Custom accent palette */
  --green: #33ff00;
  --amber: #FFB000;
  --purple: #af87ff;
  --cyan: #00d7ff;
  --pink: #ff87d7;
  --red: #ff6b6b;
  --border: #2a2a2a;
  --border-active: #ff87d7;
}

* {
  font-family: "JetBrains Mono", "Fira Code", "SF Mono", monospace;
}

body {
  background: var(--bg);
  color: var(--fg);
}
```

**Step 3: Write the app shell layout**

```heex
<%# app.html.heex — TUI chrome %>
<div class="h-screen flex flex-col font-mono">
  <%# Navigation sidebar + main content %>
  <div class="flex flex-1 overflow-hidden">
    <%# Sidebar %>
    <nav class="w-48 border-r border-[var(--border)] p-2 flex flex-col gap-1">
      <div class="text-[var(--amber)] font-bold mb-2">ExCortex</div>
      <.nav_link label="Cortex" key="c" path={~p"/cortex"} active={@active_screen == :cortex} />
      <.nav_link label="Neurons" key="n" path={~p"/neurons"} active={@active_screen == :neurons} />
      <.nav_link label="Thoughts" key="t" path={~p"/thoughts"} active={@active_screen == :thoughts} />
      <.nav_link label="Memory" key="m" path={~p"/memory"} active={@active_screen == :memory} />
      <.nav_link label="Senses" key="s" path={~p"/senses"} active={@active_screen == :senses} />
      <.nav_link label="Instinct" key="i" path={~p"/instinct"} active={@active_screen == :instinct} />
      <.nav_link label="Guide" key="g" path={~p"/guide"} active={@active_screen == :guide} />
    </nav>

    <%# Main content %>
    <main class="flex-1 overflow-auto p-4">
      {@inner_content}
    </main>
  </div>

  <%# Status bar %>
  <footer class="h-6 border-t border-[var(--border)] px-2 flex items-center text-xs text-[var(--fg-dim)]">
    <span class="text-[var(--green)]">●</span>
    <span class="ml-1">ready</span>
    <span class="ml-auto">[?] help</span>
  </footer>
</div>
```

**Step 4: Add keyboard navigation JS hook**

```javascript
// assets/js/hooks/keyboard_nav.js
export const KeyboardNav = {
  mounted() {
    this.handleKeydown = (e) => {
      // Don't capture when typing in inputs
      if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") return;

      const routes = {
        "c": "/cortex",
        "n": "/neurons",
        "t": "/thoughts",
        "m": "/memory",
        "s": "/senses",
        "i": "/instinct",
        "g": "/guide",
      };

      if (routes[e.key]) {
        e.preventDefault();
        this.pushEvent("navigate", { to: routes[e.key] });
      }
    };
    window.addEventListener("keydown", this.handleKeydown);
  },
  destroyed() {
    window.removeEventListener("keydown", this.handleKeydown);
  }
};
```

**Step 5: Remove SaladUI dependency**

Remove `salad_ui` from `mix.exs` deps. Remove `assets/css/salad_ui.css`. Remove all `import SaladUI.*` from LiveViews and components.

**Step 6: Compile and verify**

```bash
mix deps.get && mix compile && mix assets.build
```

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: replace SaladUI with WebTUI/Tokyo Night styling, add keyboard nav"
```

---

### Task 9: Base Web Components

Build the shared component library for the TUI-styled web frontend.

**Files:**
- Create: `lib/ex_cortex_web/components/tui.ex`

**Step 1: Write the TUI component library**

```elixir
defmodule ExCortexWeb.Components.TUI do
  @moduledoc "TUI-styled components: panels, status indicators, key hints."
  use Phoenix.Component

  attr :title, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <div class={"border border-[var(--border)] rounded-sm #{@class}"}>
      <div class="border-b border-[var(--border)] px-2 py-1 text-[var(--amber)] text-sm font-bold">
        ┌─ {@title} ─
      </div>
      <div class="p-2">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :color, :string, default: "green"
  attr :label, :string, required: true

  def status(assigns) do
    color_class = case assigns.color do
      "green" -> "text-[var(--green)]"
      "amber" -> "text-[var(--amber)]"
      "red" -> "text-[var(--red)]"
      "cyan" -> "text-[var(--cyan)]"
      "pink" -> "text-[var(--pink)]"
      _ -> "text-[var(--fg-dim)]"
    end
    assigns = assign(assigns, :color_class, color_class)

    ~H"""
    <span>
      <span class={@color_class}>●</span>
      <span class="ml-1">{@label}</span>
    </span>
    """
  end

  attr :hints, :list, required: true  # [{key, label}, ...]

  def key_hints(assigns) do
    ~H"""
    <div class="flex gap-4 text-xs text-[var(--fg-dim)]">
      <span :for={{key, label} <- @hints}>
        <span class="text-[var(--cyan)]">[{key}]</span> {label}
      </span>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :key, :string, required: true
  attr :path, :string, required: true
  attr :active, :boolean, default: false

  def nav_link(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class={"block px-2 py-1 text-sm #{if @active, do: "text-[var(--amber)] bg-[var(--bg-highlight)]", else: "text-[var(--fg-dim)] hover:text-[var(--fg)]"}"}
    >
      <span class="text-[var(--cyan)]">[{@key}]</span> {@label}
    </.link>
    """
  end
end
```

**Step 2: Import in html_helpers**

Add `import ExCortexWeb.Components.TUI` to the `html_helpers` function in `ex_cortex_web.ex`.

**Step 3: Compile and verify**

```bash
mix compile
```

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add TUI base components (panel, status, key_hints, nav_link)"
```

---

### Task 10: Cortex Screen (Dashboard)

The main monitoring dashboard — replaces Lodge.

**Files:**
- Create: `lib/ex_cortex_web/live/cortex_live.ex`
- Delete: `lib/ex_cortex_web/live/lodge_live.ex` (if not already renamed)

**Step 1: Implement CortexLive**

Shows four panels: Active Thoughts, Signals, Cluster Health, Recent Memory.
Subscribe to PubSub topics: `"thoughts"`, `"signals"`, `"memory"`.
Load active thought runs, recent signals, cluster status, recent engrams.

Key data fetches:
- `ExCortex.Thoughts.list_active_runs()`
- `ExCortex.Memory.list_signals(status: "active", limit: 10)`
- `ExCortex.Clusters.list_clusters_with_health()`
- `ExCortex.Memory.list_engrams(limit: 10)`

Render using `<.panel>` components with TUI styling.

**Step 2: Verify in browser**

```bash
mix phx.server
# visit http://localhost:4001/cortex
```

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add Cortex screen (monitoring dashboard)"
```

---

### Task 11: Neurons Screen

Team + agent management — replaces Guild Hall, absorbs Town Square.

**Files:**
- Create: `lib/ex_cortex_web/live/neurons_live.ex`

**Step 1: Implement NeuronsLive**

Two-panel layout:
- Left: Clusters list (expandable to show member neurons)
- Right: Detail view for selected neuron (system prompt, tier, model, trust)

Actions: install pathway, create custom neuron, edit neuron, delete, tier up/down.

Port logic from `guild_hall_live.ex` and `town_square_live.ex`:
- Cluster management from guild_hall
- Pathway installation from town_square's charter browser

**Step 2: Verify in browser**

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add Neurons screen (cluster + agent management)"
```

---

### Task 12: Thoughts Screen

Pipeline builder + run history — replaces Quests, absorbs Evaluate.

**Files:**
- Create: `lib/ex_cortex_web/live/thoughts_live.ex`

**Step 1: Implement ThoughtsLive**

Three sections:
- Thought list (with status, trigger type, schedule)
- Ad-hoc thought runner (text input → select cluster → run, replaces evaluate)
- Run detail view (impulse chain with results + recall path trace)

Port logic from `quests_live.ex` and `evaluate_live.ex`.

**Step 2: Verify in browser**

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add Thoughts screen (pipeline builder + ad-hoc runs)"
```

---

### Task 13: Memory Screen

Engram browser with tiered drill-down — replaces Grimoire.

**Files:**
- Create: `lib/ex_cortex_web/live/memory_live.ex`

**Step 1: Implement MemoryLive**

Features:
- Category tabs (all / episodic / semantic / procedural)
- Engram list showing L0 impressions by default
- Click to expand → show L1 recall
- Click again → show L2 full body
- Search with tag filtering
- Create manual engrams
- Recall path viewer (which thoughts used this engram)

**Step 2: Verify in browser**

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add Memory screen (engram browser with L0/L1/L2 tiers)"
```

---

### Task 14: Senses Screen

Source management — replaces Library, absorbs source config.

**Files:**
- Create: `lib/ex_cortex_web/live/senses_live.ex`

**Step 1: Implement SensesLive**

Features:
- Active senses list with status
- Add new sense (type selection, config form)
- Reflex library (pre-built sense templates, was Books)
- Sense activity log

Port logic from `library_live.ex` and source management from settings.

**Step 2: Verify in browser**

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add Senses screen (source management + reflex library)"
```

---

### Task 15: Instinct Screen + Guide Screen

Configuration and documentation.

**Files:**
- Create: `lib/ex_cortex_web/live/instinct_live.ex`
- Modify: `lib/ex_cortex_web/live/guide_live.ex`

**Step 1: Implement InstinctLive**

Port from `settings_live.ex` with new vocabulary:
- LLM provider config (Ollama URL, API keys)
- Default tiers and model assignments
- Feature flags
- Lobe selection (tech/lifestyle/business)
- Neuroplasticity toggle + schedule

**Step 2: Update GuideLive**

Update terminology throughout. Add DON'T PANIC header. Update onboarding flow to reference new concepts (clusters, neurons, thoughts).

**Step 3: Verify in browser**

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add Instinct screen (config) and update Guide"
```

---

### Task 16: Delete Old LiveViews + SaladUI Cleanup

Remove everything that's been replaced.

**Files to delete:**
- `lib/ex_cortex_web/live/lodge_live.ex`
- `lib/ex_cortex_web/live/town_square_live.ex`
- `lib/ex_cortex_web/live/guild_hall_live.ex`
- `lib/ex_cortex_web/live/quests_live.ex`
- `lib/ex_cortex_web/live/grimoire_live.ex`
- `lib/ex_cortex_web/live/library_live.ex`
- `lib/ex_cortex_web/live/evaluate_live.ex`
- `lib/ex_cortex_web/live/settings_live.ex`
- `lib/ex_cortex_web/components/lodge_cards.ex`
- `assets/css/salad_ui.css`
- Any remaining SaladUI component files

**Step 1: Delete files**

**Step 2: Remove any remaining SaladUI imports**

```bash
grep -r "SaladUI" lib/ --include="*.ex" --include="*.heex"
```

Fix all remaining references.

**Step 3: Compile clean**

```bash
mix compile --warnings-as-errors
```

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: delete old LiveViews and SaladUI remnants"
```

---

## Phase 4: TUI Frontend (Owl)

### Task 17: Owl Setup + App Shell

Set up the Owl dependency and create the TUI app shell with screen routing.

**Files:**
- Modify: `mix.exs` (add owl dep)
- Create: `lib/ex_cortex_tui/app.ex`
- Create: `lib/ex_cortex_tui/router.ex`
- Create: `lib/ex_cortex/mix/tasks/cortex.ex` (mix cortex task)

**Step 1: Add Owl dependency**

```elixir
# mix.exs deps
{:owl, "~> 0.12"}
```

```bash
mix deps.get
```

**Step 2: Create TUI app**

```elixir
defmodule ExCortexTUI.App do
  @moduledoc "Owl-based terminal UI for ExCortex."

  @behaviour Owl.App

  alias ExCortexTUI.Router

  @impl true
  def init(_args) do
    # Subscribe to PubSub for live updates
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "thoughts")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "signals")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "memory")

    %{screen: :cortex}
  end

  @impl true
  def handle_input(input, state) do
    case Router.handle_key(input, state.screen) do
      {:switch, screen} -> %{state | screen: screen}
      :ignore -> state
    end
  end

  @impl true
  def render(state) do
    Router.render(state.screen, state)
  end
end
```

**Step 3: Create Router**

```elixir
defmodule ExCortexTUI.Router do
  @moduledoc "Routes keyboard input and renders the active screen."

  alias ExCortexTUI.Screens

  @screen_keys %{
    "c" => :cortex,
    "n" => :neurons,
    "t" => :thoughts,
    "m" => :memory,
    "s" => :senses,
    "i" => :instinct,
    "g" => :guide
  }

  def handle_key(%{key: key}, _current_screen) when is_map_key(@screen_keys, key) do
    {:switch, Map.fetch!(@screen_keys, key)}
  end

  def handle_key(_input, _screen), do: :ignore

  def render(:cortex, state), do: Screens.Cortex.render(state)
  def render(:neurons, state), do: Screens.Neurons.render(state)
  def render(:thoughts, state), do: Screens.Thoughts.render(state)
  def render(:memory, state), do: Screens.Memory.render(state)
  def render(:senses, state), do: Screens.Senses.render(state)
  def render(:instinct, state), do: Screens.Instinct.render(state)
  def render(:guide, state), do: Screens.Guide.render(state)
end
```

**Step 4: Create mix cortex task**

```elixir
defmodule Mix.Tasks.Cortex do
  @moduledoc "Start the ExCortex TUI."
  use Mix.Task

  @shortdoc "Start ExCortex terminal UI"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    Owl.App.start(ExCortexTUI.App)
  end
end
```

**Step 5: Add conditional TUI start to application.ex**

```elixir
# In application.ex, after Endpoint:
if System.get_env("TUI") == "1" do
  children ++ [{ExCortexTUI.App, []}]
else
  children
end
```

**Step 6: Compile and test**

```bash
mix compile
mix cortex  # should launch TUI
```

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: add Owl TUI app shell with screen router and mix cortex task"
```

---

### Task 18: TUI Components

Build the shared Owl component library mirroring the web components.

**Files:**
- Create: `lib/ex_cortex_tui/components/panel.ex`
- Create: `lib/ex_cortex_tui/components/status.ex`
- Create: `lib/ex_cortex_tui/components/key_hints.ex`

**Step 1: Implement Panel component**

```elixir
defmodule ExCortexTUI.Components.Panel do
  @moduledoc "Bordered panel with title, rendered in terminal."

  def render(title, content, opts \\ []) do
    width = Keyword.get(opts, :width, 40)
    border_line = String.duplicate("─", width - String.length(title) - 4)

    [
      "┌─ #{title} #{border_line}┐",
      content
      |> String.split("\n")
      |> Enum.map(fn line ->
        padded = String.pad_trailing(line, width - 2)
        "│ #{padded}│"
      end),
      "└#{String.duplicate("─", width)}┘"
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end
end
```

**Step 2: Implement Status component**

```elixir
defmodule ExCortexTUI.Components.Status do
  def render(color, label) do
    dot = case color do
      :green -> IO.ANSI.green() <> "●" <> IO.ANSI.reset()
      :amber -> IO.ANSI.yellow() <> "●" <> IO.ANSI.reset()
      :red -> IO.ANSI.red() <> "●" <> IO.ANSI.reset()
      :cyan -> IO.ANSI.cyan() <> "●" <> IO.ANSI.reset()
      _ -> "●"
    end
    "#{dot} #{label}"
  end
end
```

**Step 3: Implement KeyHints component**

```elixir
defmodule ExCortexTUI.Components.KeyHints do
  def render(hints) do
    hints
    |> Enum.map(fn {key, label} ->
      IO.ANSI.cyan() <> "[#{key}]" <> IO.ANSI.reset() <> " #{label}"
    end)
    |> Enum.join("  ")
  end
end
```

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add TUI components (panel, status, key_hints)"
```

---

### Task 19: TUI Screens

Implement all six TUI screens using Owl + the component library.

**Files:**
- Create: `lib/ex_cortex_tui/screens/cortex.ex`
- Create: `lib/ex_cortex_tui/screens/neurons.ex`
- Create: `lib/ex_cortex_tui/screens/thoughts.ex`
- Create: `lib/ex_cortex_tui/screens/memory.ex`
- Create: `lib/ex_cortex_tui/screens/senses.ex`
- Create: `lib/ex_cortex_tui/screens/instinct.ex`
- Create: `lib/ex_cortex_tui/screens/guide.ex`

Each screen mirrors its web counterpart:
- Fetches same data from `ExCortex.*` contexts
- Renders using TUI components
- Handles local keyboard input (j/k navigation, Enter to expand, / to search)

**Step 1: Implement Cortex screen (most complex)**

Four panels: Active Thoughts, Signals, Cluster Health, Recent Memory.
Uses `Panel.render/3` for each section. Data from same context functions as web.

**Step 2: Implement remaining screens**

Follow the same pattern for each. Each screen is a module with:
- `render(state)` — returns string to display
- `handle_input(input, state)` — handles screen-local keys

**Step 3: Test each screen**

```bash
mix cortex
# press c, n, t, m, s, i, g to switch between screens
```

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add all TUI screens (cortex, neurons, thoughts, memory, senses, instinct, guide)"
```

---

## Phase 5: Packaging

### Task 20: Burrito Setup

Package the app as a standalone binary.

**Files:**
- Modify: `mix.exs` (add burrito dep + release config)
- Create: `rel/` directory if needed

**Step 1: Add Burrito dependency**

```elixir
# mix.exs
{:burrito, "~> 1.0"}
```

**Step 2: Configure release**

```elixir
# mix.exs project config
def project do
  [
    app: :ex_cortex,
    # ...
    releases: [
      ex_cortex: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            linux_x86: [os: :linux, cpu: :x86_64],
            linux_arm: [os: :linux, cpu: :aarch64],
            macos_arm: [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  ]
end
```

**Step 3: Build and test**

```bash
MIX_ENV=prod mix release ex_cortex
# Test the binary
./_build/prod/rel/ex_cortex/bin/ex_cortex
```

**Step 4: Update Dockerfile and docker-compose.yml**

Update to build the Burrito binary. The binary should be the entrypoint.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Burrito packaging for standalone ./ex_cortex binary"
```

---

## Phase 6: Cleanup

### Task 21: Port Tests

Update all existing tests to use new module names and vocabulary.

**Files:**
- All files in `test/`

**Step 1: Global rename in test files**

Same find-and-replace as Task 0 but specifically for test files:
- `ExCalibur` → `ExCortex`
- Schema references to new names
- Route paths to new routes

**Step 2: Write new tests for memory system**

Ensure coverage for:
- `ExCortex.Memory` context (CRUD, tiered query)
- `ExCortex.Memory.Extractor`
- `ExCortex.Memory.TierGenerator`
- `ExCortex.Memory.RecallPath`

**Step 3: Run full test suite**

```bash
mix test
```

Fix all failures.

**Step 4: Commit**

```bash
git add -A
git commit -m "test: port all tests to ExCortex vocabulary, add memory system tests"
```

---

### Task 22: Update CLAUDE.md + Docs

Update all documentation to reflect new vocabulary and structure.

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md` (if exists)
- Modify: guide content (whatever GuideLive renders)

**Step 1: Rewrite CLAUDE.md**

Replace all guild terminology with cortex vocabulary. Update:
- Shell commands (`mix cortex`, etc.)
- Page descriptions
- Terminology map
- Quality tools
- Key patterns
- Gotchas

**Step 2: Commit**

```bash
git add -A
git commit -m "docs: update CLAUDE.md and docs for ExCortex vocabulary"
```

---

### Task 23: Regenerate Excessibility Snapshots

After all UI changes, regenerate the accessibility HTML snapshots.

**Files:**
- `test/excessibility/html_snapshots/*`

**Step 1: Run excessibility**

```bash
mix excessibility
```

**Step 2: Commit**

```bash
git add -A
git commit -m "chore: regenerate excessibility snapshots for ExCortex UI"
```

---

### Task 24: Final Verification

Full end-to-end verification that everything works.

**Step 1: Clean compile**

```bash
mix clean && mix compile --warnings-as-errors
```

**Step 2: Run all tests**

```bash
mix test
```

**Step 3: Run credo**

```bash
mix credo --all
```

**Step 4: Format check**

```bash
mix format --check-formatted
```

**Step 5: Start web server and verify all 6 screens**

```bash
mix phx.server
# Visit each route: /cortex, /neurons, /thoughts, /memory, /senses, /instinct, /guide
```

**Step 6: Start TUI and verify all screens**

```bash
mix cortex
# Press c, n, t, m, s, i, g
```

**Step 7: Build Burrito binary**

```bash
MIX_ENV=prod mix release ex_cortex
```

**Step 8: Commit final state**

```bash
git add -A
git commit -m "chore: ExCortex v1.0.0 — complete rename and redesign"
```
