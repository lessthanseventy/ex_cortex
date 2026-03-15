# Wonder / Muse / Ruminate — Design

**Goal:** Add three tiers of cognitive interaction — ephemeral chat (Wonder), data-grounded chat (Muse), and structured persistent queries (Thought/Rumination) — completing the brain metaphor with a coherent spectrum from casual to complex.

**Architecture:** New `thoughts` table for single-step queries. Rename current `thoughts` table to `ruminations`. New LiveViews for `/wonder`, `/muse`, `/thoughts`, `/ruminations`. RAG module (`ExCortex.Muse`) for data-grounded queries.

---

## Vocabulary

| Term | Scope | Persistence | Data Grounding |
|------|-------|-------------|----------------|
| Wondering | Ephemeral LLM chat | Stored in `thoughts` table, deletable | None — pure LLM |
| Musing | Ephemeral data-grounded chat | Stored in `thoughts` table, deletable | RAG over engrams, axioms, senses |
| Thought | Saved single-step query template | Persistent, re-runnable, schedulable | RAG with optional filters |
| Rumination | Multi-step pipeline | Persistent, triggered/scheduled | Full pipeline with synapses |

The spectrum: **Wonder → Muse → Thought → Rumination** (increasing complexity and persistence).

A Wondering is a Musing with no data. A Thought is a saved Musing. A Rumination is a multi-step Thought.

---

## Data Model

### New `thoughts` table

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| question | text | What the user asked |
| answer | text | LLM response |
| scope | string | `"wonder"`, `"muse"`, `"thought"` |
| source_filters | array of strings | Optional — limit RAG to specific tags, source types |
| synapse_id | integer | Optional FK — synapse config for LLM call |
| status | string | `"draft"`, `"complete"`, `"saved"` |
| tags | array of strings | For organization |
| timestamps | | |

### Renamed `ruminations` table (currently `thoughts`)

Same schema as current `thoughts` — `name`, `description`, `status`, `trigger`, `schedule`, `steps`, `source_ids`, `engram_trigger_tags`, `signal_trigger_types`, `signal_trigger_tags`. Table and model name change only.

### FK changes

- `daydreams.thought_id` → `daydreams.rumination_id`
- `engrams.thought_id` → `engrams.rumination_id`
- `signals.thought_id` → `signals.rumination_id`
- `proposals.thought_id` stays as-is or becomes `proposals.synapse_id` (already done)

---

## Routes & UI

| Route | LiveView | Purpose |
|-------|----------|---------|
| `/wonder` | `WonderLive` | Pure LLM chat |
| `/muse` | `MuseLive` | Data-grounded chat with optional source filters |
| `/thoughts` | `ThoughtsLive` | Saved thought templates — browse, edit, re-run |
| `/ruminations` | `RuminationsLive` | Multi-step pipeline builder and run history |

### Wonder & Muse UI

Chat interface — input box at bottom, messages above. Muse adds a collapsible filter panel (tags, source types, date range). Both have a "Save to memory" button on any response to create an engram from the Q&A pair.

### Thoughts UI

List of saved thought templates. Shows question, scope, last answer. Click to re-run or edit. Can be scheduled — when scheduled, results auto-save as engrams.

### Cortex dashboard

Quick-muse input bar at the top of `/cortex` — type a question, get an inline answer or navigate to `/muse`.

---

## Architecture

### Musing flow

1. User types question in `/muse`
2. `ExCortex.Muse` gathers context via RAG — searches engrams by tags/similarity, pulls relevant axioms, optionally filters by source
3. Builds prompt: system context + gathered data + user question
4. Sends to LLM via existing `ExCortex.LLM` (Ollama/Claude fallback chain)
5. Streams response back to LiveView
6. Persists to `thoughts` table with `scope: "muse"`, `status: "complete"`
7. User can hit "Save to memory" → creates engram with `category: "episodic"`

### Wondering flow

Same as Musing but skip RAG — no data grounding, just raw LLM.

### Saved Thought flow

A Musing with `status: "saved"`. Can be re-run on demand or on a schedule. When scheduled, results auto-save as engrams.

### Key modules

- `ExCortex.Muse` — new module. RAG context gathering + single-step LLM execution. Simpler than `ImpulseRunner` (no roster/escalation/loop logic).
- `ExCortex.Thoughts` — new context module for the new `thoughts` table (CRUD, history, scheduling).
- `ExCortex.Ruminations` — renamed from current `ExCortex.Thoughts`. All multi-step pipeline logic.
- `ExCortex.Ruminations.Runner` — renamed from `ExCortex.Thoughts.Runner`.
- `ExCortex.Workers.RuminationWorker` — renamed from `ThoughtWorker`.

### Implementation reuse

- RAG: `Memory.query/2` for engrams, `Lexicon` for axioms
- LLM: existing `ExCortex.LLM.Ollama` / `ExCortex.LLM.Claude`
- Streaming: Phoenix LiveView async assigns
- `ImpulseRunner` stays for Rumination synapses — Muse is a separate, simpler path

---

## Rumination rename

Mechanical rename of the current `Thought` pipeline system:

| Current | New |
|---------|-----|
| `ExCortex.Thoughts` (context) | `ExCortex.Ruminations` |
| `ExCortex.Thoughts.Thought` (schema) | `ExCortex.Ruminations.Rumination` |
| `ExCortex.Thoughts.Runner` | `ExCortex.Ruminations.Runner` |
| `ExCortex.Thoughts.Synapse` | `ExCortex.Ruminations.Synapse` |
| `ExCortex.Thoughts.Daydream` | `ExCortex.Ruminations.Daydream` |
| `ExCortex.Thoughts.Impulse` | `ExCortex.Ruminations.Impulse` |
| `ExCortex.Thoughts.ImpulseRunner` | `ExCortex.Ruminations.ImpulseRunner` |
| `ExCortex.Thoughts.Debouncer` | `ExCortex.Ruminations.Debouncer` |
| `ExCortex.Thoughts.Scheduler` | `ExCortex.Ruminations.Scheduler` |
| `ExCortex.Thoughts.Throttle` | `ExCortex.Ruminations.Throttle` |
| `ExCortex.Thoughts.Proposal` | `ExCortex.Ruminations.Proposal` |
| `ExCortex.Workers.ThoughtWorker` | `ExCortex.Workers.RuminationWorker` |
| `thoughts` table | `ruminations` |
| `thought_id` FK | `rumination_id` |

New `ExCortex.Thoughts` becomes the context module for the simple `thoughts` table.

---

## Complete Brain Vocabulary

| Term | What it is |
|------|-----------|
| Wondering | Ephemeral LLM chat, no data grounding |
| Musing | Ephemeral LLM chat grounded in your data |
| Thought | Saved/templated single-step query |
| Rumination | Multi-step pipeline |
| Daydream | A single run of a Rumination |
| Synapse | A pipeline step |
| Impulse | A step run |
| Engram | A memory |
| Signal | A dashboard card |
| Cluster | An agent team |
| Neuron | An agent/role |
| Pathway | A team definition |
| Sense | A data source |
| Reflex | A source template |
| Expression | A notification channel |
| Axiom | A reference dataset |
| Lexicon | The collection of axioms |
| Cortex | The dashboard |
| Instinct | Settings/configuration |
| Neuroplasticity | Self-improvement loop |
