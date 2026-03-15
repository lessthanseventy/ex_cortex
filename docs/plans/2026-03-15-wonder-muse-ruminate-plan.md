# Wonder / Muse / Ruminate Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Rename current Thought pipeline system to Rumination, then build three tiers of cognitive interaction — Wonder (pure LLM chat), Muse (data-grounded RAG chat), and Thought (saved query templates).

**Architecture:** Phase 1 is a mechanical rename (Thought→Rumination) across schemas, contexts, runners, workers, tests, and LiveViews. Phase 2 builds the new Thought schema, Muse RAG module, and three new LiveViews (Wonder, Muse, Thoughts). Both phases include DB migrations.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto, PostgreSQL, ReqLLM (Ollama/Claude)

---

## Phase 1: Rename Thought → Rumination

### Task 0: DB migration — rename thoughts table to ruminations

**Files:**
- Create: `priv/repo/migrations/20260316000000_rename_thoughts_to_ruminations.exs`

**Step 1: Write the migration**

```elixir
defmodule ExCortex.Repo.Migrations.RenameThoughtsToRuminations do
  use Ecto.Migration

  def change do
    rename table(:thoughts), to: table(:ruminations)
    rename table(:daydreams), :thought_id, to: :rumination_id
    rename table(:engrams), :thought_id, to: :rumination_id
    rename table(:signals), :thought_id, to: :rumination_id
  end
end
```

**Step 2: Run migration**

```bash
mix ecto.migrate
```

**Step 3: Commit**

---

### Task 1: Rename Ecto schemas — Thought → Rumination

**Files:**
- Rename: `lib/ex_cortex/thoughts/thought.ex` → `lib/ex_cortex/ruminations/rumination.ex`
- Rename: `lib/ex_cortex/thoughts/daydream.ex` → `lib/ex_cortex/ruminations/daydream.ex`
- Rename: `lib/ex_cortex/thoughts/synapse.ex` → `lib/ex_cortex/ruminations/synapse.ex`
- Rename: `lib/ex_cortex/thoughts/impulse.ex` → `lib/ex_cortex/ruminations/impulse.ex`
- Rename: `lib/ex_cortex/thoughts/proposal.ex` → `lib/ex_cortex/ruminations/proposal.ex`
- Rename: `lib/ex_cortex/thoughts/runner.ex` → `lib/ex_cortex/ruminations/runner.ex`
- Rename: `lib/ex_cortex/thoughts/impulse_runner.ex` → `lib/ex_cortex/ruminations/impulse_runner.ex`
- Rename: `lib/ex_cortex/thoughts/scheduler.ex` → `lib/ex_cortex/ruminations/scheduler.ex`
- Rename: `lib/ex_cortex/thoughts/debouncer.ex` → `lib/ex_cortex/ruminations/debouncer.ex`
- Rename: `lib/ex_cortex/thoughts/throttle.ex` → `lib/ex_cortex/ruminations/throttle.ex`
- Rename: `lib/ex_cortex/thoughts.ex` → `lib/ex_cortex/ruminations.ex`
- Rename: `lib/ex_cortex/workers/thought_worker.ex` → `lib/ex_cortex/workers/rumination_worker.ex`

**Changes in each file:**
- Module name: `ExCortex.Thoughts.*` → `ExCortex.Ruminations.*`
- `Rumination` schema: table name `"ruminations"`, all `thought_id` refs → `rumination_id`
- `Daydream` schema: `thought_id` field → `rumination_id`
- Context module: all function names like `list_thoughts` → `list_ruminations`, `create_thought` → `create_rumination`
- Worker: `ThoughtWorker` → `RuminationWorker`, `"thought_id"` arg → `"rumination_id"`
- Runner: log tags `[ThoughtRunner]` → `[RuminationRunner]`

**Step 1: Create `lib/ex_cortex/ruminations/` directory, move and rename all files**
**Step 2: Update all module names and internal references**
**Step 3: Delete old `lib/ex_cortex/thoughts/` directory**
**Step 4: Compile — fix any broken references**
**Step 5: Commit**

---

### Task 2: Update all callers of Thoughts → Ruminations

**Files:**
- Modify: `lib/ex_cortex/application.ex` — `Thoughts.Debouncer` → `Ruminations.Debouncer`, `Thoughts.Scheduler` → `Ruminations.Scheduler`
- Modify: `lib/ex_cortex/evaluator.ex` — any `Thoughts.*` refs
- Modify: `lib/ex_cortex/board.ex` — `Thoughts.list_synapses` → `Ruminations.list_synapses`, `Thoughts.create_thought` → `Ruminations.create_rumination`, etc.
- Modify: `lib/ex_cortex/memory.ex` — `thought_id` → `rumination_id`
- Modify: `lib/ex_cortex/memory/extractor.ex` — `thought_id` → `rumination_id`
- Modify: `lib/ex_cortex/signals.ex` — `thought_id` → `rumination_id`
- Modify: `lib/ex_cortex/signals/trigger_runner.ex` — `Thoughts.*` refs
- Modify: `lib/ex_cortex/memory/engram_trigger_runner.ex` — `Thoughts.*` refs
- Modify: `lib/ex_cortex/senses/worker.ex` — `Thoughts.*` refs
- Modify: `lib/ex_cortex/neuroplasticity/seed.ex` — `Thoughts.*` refs
- Modify: `lib/ex_cortex/app_telemetry.ex` — `thought_id` → `rumination_id`
- Modify: `lib/ex_cortex/context_providers/thought_history.ex` — rename to `rumination_history.ex`, update module
- Modify: `lib/ex_cortex/context_providers/context_provider.ex` — `"thought_history"` → `"rumination_history"`, `"thought_output"` → `"rumination_output"`
- Modify: `lib/ex_cortex/tools/run_thought.ex` — rename to `run_rumination.ex`, tool name `"run_thought"` → `"run_rumination"`
- Modify: `lib/ex_cortex/tools/registry.ex` — `RunThought` → `RunRumination`
- Modify: all `lib/ex_cortex/pathways/*.ex` — `"run_thought"` → `"run_rumination"` in loop_tools
- Modify: all `lib/ex_cortex/board/*.ex` — any `thought_definition` refs → `rumination_definition`
- Modify: `lib/ex_cortex_tui/screens/cortex.ex` — `Thoughts.*` refs
- Modify: `lib/ex_cortex_web/live/cortex_live.ex` — `Thoughts.*` refs
- Modify: `lib/ex_cortex_web/live/thoughts_live.ex` — rename to `ruminations_live.ex`, update module to `RuminationsLive`
- Modify: `lib/ex_cortex_web/router.ex` — `ThoughtsLive` → `RuminationsLive`, route `/thoughts` → `/ruminations`
- Modify: `lib/ex_cortex/llm/claude.ex` — `thought_id` → `rumination_id`
- Modify: `lib/ex_cortex/llm/ollama.ex` — `thought_id` → `rumination_id`

**Step 1: Update all files (use subagents for parallel work)**
**Step 2: Compile — zero warnings**
**Step 3: Commit**

---

### Task 3: Rename all test files and update test content

**Files:**
- Rename + update: all `test/ex_cortex/thought_*` → `test/ex_cortex/rumination_*`
- Rename + update: `test/ex_cortex/thoughts_test.exs` → `test/ex_cortex/ruminations_test.exs`
- Rename + update: `test/ex_cortex/thought_runner/` → `test/ex_cortex/rumination_runner/`
- Update: all test files referencing `Thoughts.*` modules
- Update: `test/ex_cortex/tools/registry_test.exs` — `"run_thought"` → `"run_rumination"`
- Update: `test/ex_cortex/integration/everyday_council_flow_test.exs` — `thought_definitions` stays (it's about synapses)
- Delete: any stale test files

**Step 1: Rename and update all test files**
**Step 2: Run full test suite — 412 tests, 0 failures**
**Step 3: Commit**

---

### Task 4: Update Engram and Signal schemas — thought_id → rumination_id

**Files:**
- Modify: `lib/ex_cortex/memory/engram.ex` — `thought_id` → `rumination_id`
- Modify: `lib/ex_cortex/signals/signal.ex` — `thought_id` → `rumination_id`
- Modify: `lib/ex_cortex/memory/recall_path.ex` — if it references thought_id
- Update any tests that reference these fields

**Step 1: Update schemas**
**Step 2: Update callers**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 5: Update CLAUDE.md and design docs

**Files:**
- Modify: `CLAUDE.md` — update vocabulary map, routes, module references
- Modify: `docs/plans/2026-03-15-wonder-muse-ruminate-design.md` — mark Phase 1 complete

**Step 1: Update docs**
**Step 2: Commit**

---

## Phase 2: Build Wonder / Muse / Thought

### Task 6: Create new Thought schema and context

**Files:**
- Create: `lib/ex_cortex/thoughts/thought.ex`
- Create: `lib/ex_cortex/thoughts.ex`
- Create: `priv/repo/migrations/20260316000001_create_thoughts.exs`
- Test: `test/ex_cortex/thoughts_test.exs`

**Step 1: Write the migration**

```elixir
defmodule ExCortex.Repo.Migrations.CreateThoughts do
  use Ecto.Migration

  def change do
    create table(:thoughts) do
      add :question, :text, null: false
      add :answer, :text
      add :scope, :string, null: false, default: "muse"
      add :source_filters, {:array, :string}, default: []
      add :status, :string, null: false, default: "draft"
      add :tags, {:array, :string}, default: []
      timestamps()
    end

    create index(:thoughts, [:scope])
    create index(:thoughts, [:status])
  end
end
```

**Step 2: Write the schema**

```elixir
defmodule ExCortex.Thoughts.Thought do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "thoughts" do
    field :question, :string
    field :answer, :string
    field :scope, :string, default: "muse"
    field :source_filters, {:array, :string}, default: []
    field :status, :string, default: "draft"
    field :tags, {:array, :string}, default: []
    timestamps()
  end

  def changeset(thought, attrs) do
    thought
    |> cast(attrs, [:question, :answer, :scope, :source_filters, :status, :tags])
    |> validate_required([:question, :scope])
    |> validate_inclusion(:scope, ~w(wonder muse thought))
    |> validate_inclusion(:status, ~w(draft complete saved))
  end
end
```

**Step 3: Write the context module**

```elixir
defmodule ExCortex.Thoughts do
  @moduledoc "Context for single-step thoughts — wonderings, musings, and saved queries."
  import Ecto.Query
  alias ExCortex.Thoughts.Thought
  alias ExCortex.Repo

  def list_thoughts(opts \\ []) do
    query = from(t in Thought, order_by: [desc: t.inserted_at])
    query = if scope = opts[:scope], do: where(query, [t], t.scope == ^scope), else: query
    query = if status = opts[:status], do: where(query, [t], t.status == ^status), else: query
    Repo.all(query)
  end

  def get_thought!(id), do: Repo.get!(Thought, id)
  def create_thought(attrs), do: %Thought{} |> Thought.changeset(attrs) |> Repo.insert()
  def update_thought(%Thought{} = t, attrs), do: t |> Thought.changeset(attrs) |> Repo.update()
  def delete_thought(%Thought{} = t), do: Repo.delete(t)

  def save_to_memory(%Thought{question: q, answer: a, tags: tags}) do
    ExCortex.Memory.create_engram(%{
      title: q,
      body: a,
      tags: tags,
      source: "muse",
      category: "episodic"
    })
  end
end
```

**Step 4: Write tests**
**Step 5: Run migration and tests**
**Step 6: Commit**

---

### Task 7: Build ExCortex.Muse — RAG context gathering

**Files:**
- Create: `lib/ex_cortex/muse.ex`
- Test: `test/ex_cortex/muse_test.exs`

**Step 1: Write the Muse module**

The Muse module:
1. Takes a question + optional source filters
2. Searches engrams by tags/text matching
3. Searches axioms by text matching
4. Builds a context string from results
5. Sends to LLM with system prompt + context + question
6. Returns the answer

```elixir
defmodule ExCortex.Muse do
  @moduledoc "Data-grounded single-step LLM queries. RAG over engrams and axioms."

  alias ExCortex.Memory
  alias ExCortex.Lexicon
  alias ExCortex.Thoughts

  @default_model "devstral-small-2:24b"

  def ask(question, opts \\ []) do
    scope = Keyword.get(opts, :scope, "muse")
    source_filters = Keyword.get(opts, :source_filters, [])
    model = Keyword.get(opts, :model, resolve_model())

    context = if scope == "muse", do: gather_context(question, source_filters), else: ""
    prompt = build_prompt(context, question)

    case ExCortex.LLM.complete(model, prompt) do
      {:ok, answer} ->
        {:ok, thought} = Thoughts.create_thought(%{
          question: question,
          answer: answer,
          scope: scope,
          source_filters: source_filters,
          status: "complete"
        })
        {:ok, thought}

      {:error, _} = err -> err
    end
  end

  defp gather_context(question, filters) do
    engrams = Memory.search_engrams(question, filters)
    axiom_results = search_axioms(question)

    parts = []
    parts = if engrams != [], do: parts ++ [format_engrams(engrams)], else: parts
    parts = if axiom_results != "", do: parts ++ [axiom_results], else: parts
    Enum.join(parts, "\n\n---\n\n")
  end

  defp search_axioms(question) do
    Lexicon.list_axioms()
    |> Enum.map(fn axiom ->
      case ExCortex.Tools.QueryAxiom.call(%{"axiom" => axiom.name, "query" => question}) do
        {:ok, result} when result != "" -> "## #{axiom.name}\n#{result}"
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp format_engrams(engrams) do
    entries = Enum.map(engrams, fn e ->
      "### #{e.title}\n#{e.recall || e.impression || String.slice(e.body || "", 0, 500)}"
    end)
    "## Relevant Memories\n\n" <> Enum.join(entries, "\n\n")
  end

  defp build_prompt("", question), do: question
  defp build_prompt(context, question) do
    """
    Use the following context to answer the question. If the context doesn't help, say so.

    #{context}

    ---

    Question: #{question}
    """
  end

  defp resolve_model do
    case Application.get_env(:ex_cortex, :model_fallback_chain) do
      [model | _] -> model
      _ -> @default_model
    end
  end
end
```

**Step 2: Write tests (mock LLM responses)**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 8: Build WonderLive — pure LLM chat

**Files:**
- Create: `lib/ex_cortex_web/live/wonder_live.ex`
- Test: `test/ex_cortex_web/live/wonder_live_test.exs`
- Modify: `lib/ex_cortex_web/router.ex` — add `/wonder` route

**Step 1: Build the LiveView**

Chat interface with:
- Mount: empty message list
- `handle_event("ask", %{"question" => q})` — calls `Muse.ask(q, scope: "wonder")` async
- `handle_info({:muse_response, thought})` — appends to message list
- "Save to memory" button per response — calls `Thoughts.save_to_memory(thought)`
- TUI components for consistent look

**Step 2: Add route**

```elixir
live "/wonder", WonderLive, :index
```

**Step 3: Write tests**
**Step 4: Run tests**
**Step 5: Commit**

---

### Task 9: Build MuseLive — data-grounded chat

**Files:**
- Create: `lib/ex_cortex_web/live/muse_live.ex`
- Test: `test/ex_cortex_web/live/muse_live_test.exs`
- Modify: `lib/ex_cortex_web/router.ex` — add `/muse` route

**Step 1: Build the LiveView**

Same chat interface as Wonder, plus:
- Collapsible filter panel (tags, source types)
- `handle_event("ask", %{"question" => q})` — calls `Muse.ask(q, scope: "muse", source_filters: filters)` async
- Filter state tracked in assigns
- Shows which data sources were consulted in the response

**Step 2: Add route**

```elixir
live "/muse", MuseLive, :index
```

**Step 3: Write tests**
**Step 4: Run tests**
**Step 5: Commit**

---

### Task 10: Build ThoughtsLive — saved query templates

**Files:**
- Create: `lib/ex_cortex_web/live/thoughts_live.ex` (new version — saved templates)
- Test: `test/ex_cortex_web/live/thoughts_live_test.exs`
- Modify: `lib/ex_cortex_web/router.ex` — add `/thoughts` route

**Step 1: Build the LiveView**

List view of saved thoughts:
- Mount: `Thoughts.list_thoughts(status: "saved")`
- Each thought shows question, scope, tags, last answer, last run time
- Click to re-run or edit
- "New Thought" button — form with question, scope selector, source filters, tags
- "Re-run" button — calls `Muse.ask(thought.question, scope: thought.scope, source_filters: thought.source_filters)`

**Step 2: Add route**

```elixir
live "/thoughts", ThoughtsLive, :index
```

**Step 3: Write tests**
**Step 4: Run tests**
**Step 5: Commit**

---

### Task 11: Add quick-muse to Cortex dashboard

**Files:**
- Modify: `lib/ex_cortex_web/live/cortex_live.ex`

**Step 1: Add a muse input bar**

At the top of the Cortex dashboard, add a text input:
- `handle_event("quick_muse", %{"question" => q})` — calls `Muse.ask(q, scope: "muse")` async
- Shows inline answer below the input
- "Open in Muse" link to navigate to `/muse` with the conversation

**Step 2: Write tests**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 12: Update navigation and CLAUDE.md

**Files:**
- Modify: `lib/ex_cortex_web/components/tui.ex` — add Wonder, Muse, Thoughts nav links
- Modify: `CLAUDE.md` — update routes, vocabulary map
- Modify: `lib/ex_cortex_web/live/guide_live.ex` — update guide text

**Step 1: Update nav links**
**Step 2: Update docs**
**Step 3: Run full test suite — 0 failures**
**Step 4: Commit**

---

### Task 13: Final verification

**Step 1: Run full grep for old vocabulary**

```bash
grep -rn 'ExCortex\.Thoughts\.' lib/ test/ | grep -v ruminations | grep -v "thoughts.ex" | grep -v "thoughts_live"
```

Expect: only references to the NEW `ExCortex.Thoughts` (single-step) module.

**Step 2: Run full test suite**

```bash
mix test
```

**Step 3: Run format + credo**

```bash
mix format && mix credo
```

**Step 4: Final commit**
