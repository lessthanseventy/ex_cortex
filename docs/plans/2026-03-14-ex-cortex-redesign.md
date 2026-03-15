# ExCortex: Full Redesign

**Date:** 2026-03-14
**Status:** Approved
**Scope:** Rename ExCalibur → ExCortex, collapse deps, new brain/consciousness vocabulary, OpenViking-style memory system, dual frontend (WebTUI + Owl TUI), Burrito standalone binary

---

## Motivation

ExCalibur's guild/fantasy metaphor served its purpose as scaffolding but is now a hindrance. The app is fundamentally **teams of agents that respond to inputs and generate outputs** — the medieval terminology obscures that. Meanwhile, the nested app structure (ex_cellence core lib + ex_calibur web app + dashboard/UI path deps) creates friction with shared Repos, duplicated supervision trees, and coordination headaches.

This redesign:
1. Renames everything to a brain/consciousness vocabulary that *describes* what the system actually does
2. Collapses all deps into a single app: **ExCortex**
3. Adds OpenViking-inspired tiered memory system (L0/L1/L2, structured categories, retrieval traces)
4. Builds dual frontends: web (Phoenix LiveView + WebTUI CSS) and terminal (Owl TUI)
5. Ships as a standalone binary via Burrito — `./ex_cortex` replaces `docker-compose up`

---

## 1. Vocabulary

| Old | New | What it is |
|---|---|---|
| Guild | **Cluster** | A group of neurons that work together |
| Member / Role | **Neuron** | An individual agent that processes signals |
| Quest | **Thought** | A pipeline — a chain of neurons firing |
| Quest step | **Impulse** | A single step in a thought chain |
| Charter | **Pathway** | A pre-built cluster configuration |
| Lore Entry | **Engram** | A stored memory |
| Lodge Card | **Signal** | A dashboard artifact |
| Source | **Sense** | An external input feed |
| Book (source blueprint) | **Reflex** | A pre-built sense template |
| Herald | **Impulse** (outbound) | An outbound notification channel |
| Banner (tech/lifestyle/business) | **Lobe** | A domain partition |
| Rank (apprentice/journeyman/master) | **Tier** | Neuron capability level |
| Self-improvement loop | **Neuroplasticity** | The system rewiring itself |
| Town Square | *deleted* | Absorbed into Neurons screen |
| Guild Hall | *deleted* | Replaced by Neurons screen |
| Lodge | *deleted* | Replaced by Cortex screen |
| Grimoire | *deleted* | Replaced by Memory screen |
| Library | *deleted* | Absorbed into Senses screen |
| Evaluate | *deleted* | Absorbed into Thoughts screen (ad-hoc run) |

---

## 2. Pages / Screens

Six screens + guide, identical in web and TUI. Keyboard shortcuts switch between them.

| Key | Route | Screen | Purpose |
|---|---|---|---|
| `c` | `/cortex` | Cortex | Monitoring dashboard — active thoughts, signals, cluster health, memory activity |
| `n` | `/neurons` | Neurons | Manage clusters + individual neurons, install pathways |
| `t` | `/thoughts` | Thoughts | Pipeline builder, run history, ad-hoc runs |
| `m` | `/memory` | Memory | Engram browser with L0/L1/L2 tier drill-down, categories, recall paths |
| `s` | `/senses` | Senses | Source management, reflex library |
| `i` | `/instinct` | Instinct | Configuration — LLM providers, tiers, models, feature flags, lobe selection |
| `g` | `/guide` | Guide | Documentation / onboarding (DON'T PANIC energy) |
| `?` | | Help | Keyboard shortcut overlay |

### Consolidation Map

| Current Page | → New Screen | What happens |
|---|---|---|
| `/town-square` | `/neurons` | Charter browsing → pathway installation inside neurons |
| `/guild-hall` | `/neurons` | Team management stays, renamed |
| `/quests` + `/quest-board` | `/thoughts` | Pipeline builder, renamed |
| `/lodge` | `/cortex` | Dashboard, renamed |
| `/grimoire` | `/memory` | Lore browser → engram browser with tiers |
| `/library` | `/senses` | Book templates → reflex templates inside senses |
| `/evaluate` | `/thoughts` | Manual eval → ad-hoc thought run |
| `/settings` | `/instinct` | Settings, renamed |
| `/guide` | `/guide` | Stays |

### Screen Layouts (TUI wireframes)

**Cortex:**
```
┌─ Active Thoughts ──────────┐ ┌─ Signals ──────────────┐
│ ▶ SI Analyst Sweep   3m12s │ │ ● Platform scan: 2 warn│
│ ▶ Tech Dispatch      0m45s │ │ ● Market close summary │
│   Science Watch   done 14m │ │ ● New engram: "api..." │
└────────────────────────────┘ └────────────────────────┘
┌─ Cluster Health ───────────┐ ┌─ Recent Memory ────────┐
│ Platform    4/4 ●●●●       │ │ L0  api auth pattern   │
│ Skeptics    3/3 ●●●        │ │ L1  deploy runbook v3  │
│ Dev Team    5/5 ●●●●●      │ │ L2  full incident rpt  │
└────────────────────────────┘ └────────────────────────┘
```

**Neurons:**
```
┌─ Clusters ───────────────────────────────────────┐
│ Platform Guild     4 neurons  tech    ●active    │
│ The Skeptics       3 neurons  tech    ●active    │
│ Tech Dispatch      5 neurons  life    ●active    │
│ ↳ [Enter] expand   [a]dd   [p]athway  [d]elete  │
└──────────────────────────────────────────────────┘
┌─ Neurons (Platform Guild) ───────────────────────┐
│ Backend Reviewer    apprentice  devstral  ●ready │
│ DevOps Reviewer     apprentice  devstral  ●ready │
│ Perf Auditor        journeyman  gemma3    ●busy  │
│ Security Skeptic    apprentice  devstral  ●ready │
│ ↳ [Enter] detail   [e]dit   [t]ier up           │
└──────────────────────────────────────────────────┘
```

**Thoughts:**
```
┌─ Thoughts ───────────────────────────────────────┐
│ SI Analyst Sweep    scheduled  4h    ●active     │
│ Platform Quick Scan source     auto  ●active     │
│ Tech Digest         scheduled  6h    ●active     │
│ ─── ad hoc ───                                   │
│ > Run a thought...                  [n]ew [r]un  │
└──────────────────────────────────────────────────┘
```

**Memory:**
```
┌─ Memory ─────────────────── filter: [all▾] ──────┐
│ ┌ episodic ──────────────────────────────────┐   │
│ │ L0 SI sweep #47: 2 issues filed       ★3  │   │
│ │ L0 Platform scan: clean run           ★2  │   │
│ └────────────────────────────────────────────┘   │
│ ┌ semantic ──────────────────────────────────┐   │
│ │ L0 API auth patterns (3 sub-entries)  ★4  │   │
│ └────────────────────────────────────────────┘   │
│ ┌ procedural ────────────────────────────────┐   │
│ │ L0 How to run credo with baseline     ★2  │   │
│ └────────────────────────────────────────────┘   │
│ [/] search  [n]ew  [Enter] expand tier           │
└──────────────────────────────────────────────────┘
```

### Keyboard Navigation

```
Global:
  c → /cortex       n → /neurons     t → /thoughts
  m → /memory       s → /senses      i → /instinct
  g → /guide        ? → help overlay

Within screens:
  j/k       → move up/down
  Enter     → expand/select
  Esc/q     → back/close
  /         → search
  Tab       → switch sub-panels
  a         → add new
  d         → delete (with confirmation)
  e         → edit
  r         → run (in /thoughts)
```

---

## 3. Data Model

### Schemas & Tables

```
ExCortex.Cluster                  # was GuildCharters.GuildCharter
  table: clusters                 # was guild_charters
  fields: name, pathway_id, lobe, config

ExCortex.Neuron                   # was BuiltinMember + Schemas.Member
  table: neurons                  # was excellence_resources (type: "role")
  fields: name, cluster_id, system_prompt, tier, model, strategy, category

ExCortex.Thought                  # was Quests.Quest
  table: thoughts                 # was excellence_quests
  fields: name, description, status, trigger, schedule, impulses, sense_ids

ExCortex.Thought.Run              # was Quests.QuestRun
  table: thought_runs             # was excellence_quest_runs

ExCortex.Thought.Impulse          # was Quests.StepRun
  table: impulses                 # was excellence_step_runs

ExCortex.Memory.Engram            # was Lore.LoreEntry
  table: engrams                  # was lore_entries
  fields: title, body, impression, recall, tags, importance, source,
          category, cluster_name, thought_run_id

ExCortex.Memory.Signal            # was Lodge.Card
  table: signals                  # was lodge_cards
  fields: type, title, body, metadata, tags, cluster_name

ExCortex.Memory.RecallPath        # NEW
  table: recall_paths
  fields: thought_run_id, engram_id, reason, relevance_score, tier_accessed, step

ExCortex.Sense                    # was Sources (various, mostly in-memory)
  table: senses                   # NEW — persisted
  fields: name, type, config, cluster_id, status

ExCortex.Pathway                  # was Charter modules
  modules: ExCortex.Pathways.*    # pre-built cluster configs
```

### Engram Tiers (from OpenViking)

| Tier | Field | Token Budget | Purpose |
|---|---|---|---|
| **L0** | `impression` | ~100 tokens | Quick abstract for search/filtering |
| **L1** | `recall` | ~1k tokens | Summary with navigation pointers |
| **L2** | `body` | Unlimited | Full content, loaded on demand |

### Memory Categories (from neuroscience)

| Category | What it stores | Mutable? |
|---|---|---|
| **episodic** | Events, thought run results — what happened | Append-only |
| **semantic** | Facts, patterns, learned knowledge | Updateable |
| **procedural** | Skills, protocols, how-to | Updateable |

---

## 4. Memory System

### Engram Lifecycle

```
Stimulus arrives
    │
    ▼
Thought runs (chain of impulses)
    │
    ▼
ExCortex.Memory.Extractor (post-thought hook)
    │
    ├── Extract episodic engram (what happened)
    ├── Extract semantic engrams (facts/patterns discovered)
    ├── Extract procedural engrams (skills/protocols used)
    │
    ▼
ExCortex.Memory.TierGenerator (async)
    │
    ├── Generate L0 impression (~100 tokens)
    ├── Generate L1 recall (~1k tokens)
    └── Store L2 body (full original content)
    │
    ▼
Engram stored + RecallPath linked to thought run
```

### Auto-Extraction

Every completed thought run triggers `ExCortex.Memory.Extractor`:
- Always creates an episodic engram (what happened)
- Asks cheapest LLM: "did this run discover any new facts or patterns?" → semantic engram
- Asks cheapest LLM: "did this run demonstrate a reusable procedure?" → procedural engram

Uses the fastest/cheapest neuron tier (ministral) — this is housekeeping.

### Tiered Recall

`query_memory` (replaces `query_lore`) uses tiered loading:

1. Search L0 impressions across all matching engrams (fast, cheap)
2. Load L1 recalls for top N matches (neuron sees summaries)
3. Load L2 body only for selected engrams (full content on demand)

Token savings: ~20k tokens (old, load all bodies) → ~6k tokens (new, tiered).

### Recall Paths

Every memory access during a thought run is logged with: which engram, why, relevance score, what tier was accessed, which impulse step. Visible in Cortex and Thoughts screens as a "memory trace" for debugging.

### Neuroplasticity (Self-Improvement)

The SI loop is reframed: each sweep creates structured engrams that future sweeps query. The brain literally gets smarter with each run — it avoids re-filing known issues, recognizes patterns from prior sweeps, and builds procedural memory about its own codebase.

---

## 5. Dual Frontend

### Architecture

```
ExCortex (single app)
├── ExCortex.Core        — neurons, thoughts, memory, senses, evaluator
├── ExCortexWeb          — Phoenix LiveView + WebTUI CSS
├── ExCortexTUI          — Owl terminal frontend
└── Burrito              — standalone binary
```

All business logic lives in `ExCortex.*` (never in LiveViews or Owl screens). Both frontends are thin render shells that call core functions and subscribe to PubSub.

### Web Frontend (WebTUI)

Replace SaladUI with WebTUI CSS (or hand-rolled equivalent if WebTUI fights Phoenix). Attribute-based styling: `box-`, `grid-`, `size-`, `color-`. All components must be representable with box-drawing characters and monospace text.

### Terminal Frontend (Owl)

Owl (by Dashbit) — LiveView-inspired terminal UI. Same assign/render component model. Each screen is an Owl LiveView equivalent. PubSub subscriptions for live updates.

Both frontends share the same component inventory with matching data contracts:

| Pattern | Web (WebTUI) | TUI (Owl) |
|---|---|---|
| Box/panel | `<div box->` | `Owl.Components.panel` |
| Table/list | `<table>` | `Owl.Components.table` |
| Status indicator | `●` unicode | same unicode |
| Selection list | `<ul>` + highlight | `Owl.Components.select` |
| Modal/overlay | positioned `<div box->` | Owl overlay |
| Progress | `[████░░░░]` text | same text |

### Color Palette

Tokyo Night dark base with custom accent colors (from tmux config):

```
Background:  #1a1b26  (Tokyo Night dark)
Foreground:  #a9b1d6  (Tokyo Night fg, body text)

Accent colors:
  #33ff00  electric green  — active, healthy, complete, "alive"
  #FFB000  amber/gold      — primary text, headings, warnings, focused
  #af87ff  soft purple     — secondary, metadata, tags
  #00d7ff  cyan            — info, selected, links
  #ff87d7  pink            — hot actions, active borders
  #ff6b6b  soft red        — error, failed, critical
  #2a2a2a  dark gray       — inactive borders, disabled
```

### Entry Points

```bash
# Development
mix phx.server           # web only (as usual)
mix cortex               # TUI only
mix phx.server --tui     # both

# Production / distribution
./ex_cortex              # Burrito binary — starts TUI + web
./ex_cortex --web        # web only
./ex_cortex --tui        # TUI only
```

---

## 6. Project Structure

```
ex_cortex/
├── lib/
│   ├── ex_cortex/
│   │   ├── application.ex
│   │   ├── repo.ex
│   │   ├── core/                    # absorbed from ex_cellence
│   │   │   ├── evaluator.ex
│   │   │   ├── strategy.ex
│   │   │   └── tool_router.ex
│   │   ├── clusters/
│   │   │   ├── cluster.ex
│   │   │   └── registry.ex
│   │   ├── neurons/
│   │   │   ├── neuron.ex
│   │   │   ├── builtin.ex
│   │   │   └── trust.ex
│   │   ├── thoughts/
│   │   │   ├── thought.ex
│   │   │   ├── impulse.ex
│   │   │   ├── run.ex
│   │   │   ├── runner.ex
│   │   │   ├── scheduler.ex
│   │   │   └── throttle.ex
│   │   ├── memory/
│   │   │   ├── engram.ex
│   │   │   ├── signal.ex
│   │   │   ├── recall_path.ex
│   │   │   ├── extractor.ex
│   │   │   ├── tier_generator.ex
│   │   │   └── query.ex
│   │   ├── senses/
│   │   │   ├── sense.ex
│   │   │   ├── supervisor.ex
│   │   │   ├── behaviour.ex
│   │   │   ├── git.ex
│   │   │   ├── directory.ex
│   │   │   ├── feed.ex
│   │   │   ├── webhook.ex
│   │   │   ├── url.ex
│   │   │   ├── websocket.ex
│   │   │   └── reflex.ex
│   │   ├── pathways/                # pre-built cluster configs
│   │   │   ├── platform.ex
│   │   │   ├── skeptics.ex
│   │   │   ├── dev_team.ex
│   │   │   ├── tech_dispatch.ex
│   │   │   ├── creative_studio.ex
│   │   │   ├── everyday_council.ex
│   │   │   ├── market_signals.ex
│   │   │   ├── sports_corner.ex
│   │   │   ├── culture_desk.ex
│   │   │   ├── science_watch.ex
│   │   │   ├── quality_collective.ex
│   │   │   └── product_intelligence.ex
│   │   ├── neuroplasticity/         # self-improvement
│   │   │   ├── analyst_sweep.ex
│   │   │   ├── loop.ex
│   │   │   └── seed.ex
│   │   ├── impulses/                # outbound notifications
│   │   │   ├── impulse.ex
│   │   │   ├── slack.ex
│   │   │   ├── webhook.ex
│   │   │   ├── github_issue.ex
│   │   │   ├── github_pr.ex
│   │   │   ├── email.ex
│   │   │   └── pager_duty.ex
│   │   ├── tools/
│   │   │   ├── query_memory.ex
│   │   │   ├── run_thought.ex
│   │   │   ├── run_sandbox.ex
│   │   │   └── ...
│   │   ├── llm.ex
│   │   ├── claude_client.ex
│   │   ├── ollama_cache.ex
│   │   └── settings.ex
│   │
│   ├── ex_cortex_web/
│   │   ├── router.ex
│   │   ├── endpoint.ex
│   │   ├── live/
│   │   │   ├── cortex_live.ex
│   │   │   ├── neurons_live.ex
│   │   │   ├── thoughts_live.ex
│   │   │   ├── memory_live.ex
│   │   │   ├── senses_live.ex
│   │   │   ├── instinct_live.ex
│   │   │   └── guide_live.ex
│   │   ├── components/
│   │   │   ├── panel.ex
│   │   │   ├── status.ex
│   │   │   ├── key_hints.ex
│   │   │   ├── neuron_card.ex
│   │   │   ├── thought_run.ex
│   │   │   ├── engram_entry.ex
│   │   │   ├── signal_card.ex
│   │   │   └── sense_row.ex
│   │   ├── hooks/
│   │   │   └── keyboard_nav.js
│   │   └── layouts/
│   │       └── app.html.heex
│   │
│   └── ex_cortex_tui/
│       ├── app.ex
│       ├── router.ex
│       ├── screens/
│       │   ├── cortex.ex
│       │   ├── neurons.ex
│       │   ├── thoughts.ex
│       │   ├── memory.ex
│       │   ├── senses.ex
│       │   └── instinct.ex
│       ├── components/
│       │   ├── panel.ex
│       │   ├── status.ex
│       │   ├── key_hints.ex
│       │   ├── neuron_card.ex
│       │   ├── thought_run.ex
│       │   ├── engram_entry.ex
│       │   ├── signal_card.ex
│       │   └── sense_row.ex
│       └── live.ex
│
├── assets/
│   ├── css/
│   │   └── app.css                  # Tokyo Night + custom palette
│   └── js/
│       └── app.js
├── priv/repo/migrations/
├── config/
├── test/
├── mix.exs                          # app: :ex_cortex
├── Dockerfile
├── docker-compose.yml
└── burrito.exs
```

---

## 7. Migration

### Database Migration

One migration renames all tables and adds new columns/tables:

- Rename: `excellence_resources` → `neurons`, `excellence_quests` → `thoughts`, `excellence_quest_runs` → `thought_runs`, `excellence_step_runs` → `impulses`, `lore_entries` → `engrams`, `lodge_cards` → `signals`, `guild_charters` → `clusters`
- Add to engrams: `impression` (L0), `recall` (L1), `category`, `cluster_name`, `thought_run_id`
- Create: `recall_paths` (thought_run_id, engram_id, reason, relevance_score, tier_accessed, step)
- Create: `senses` (name, type, config, cluster_id, status)
- Add indexes: engrams(category), engrams(cluster_name), engrams(tags) GIN, recall_paths(thought_run_id), recall_paths(engram_id)

### Dependency Absorption

| Dep | What we take | Where it goes |
|---|---|---|
| `ex_cellence` | Evaluator, Strategy, ResourceDefinition, Oban workers | `ExCortex.Core.*` |
| `ex_cellence_dashboard` | Chart components, viz helpers | `ExCortexWeb.Components.*` |
| `ex_cellence_ui` | Form components | `ExCortexWeb.Components.*` |

All three path deps removed from `mix.exs`. One app, one supervision tree, one Ecto repo.

### What Gets Deleted

- All old LiveViews (town_square, guild_hall, lodge, grimoire, library, quests, evaluate, settings)
- All SaladUI imports and component usage
- All ex_cellence / ex_cellence_dashboard / ex_cellence_ui dep references

---

## 8. Inspirations

- **OpenViking** (volcengine) — L0/L1/L2 tiered context, structured memory categories, retrieval trajectory visualization, session compression
- **WebTUI** — CSS library for terminal UI aesthetics in the browser
- **Owl** (Dashbit) — LiveView-inspired terminal UI framework for Elixir
- **Burrito** — wrap Elixir releases as standalone binaries
- **Douglas Adams / Hackers / Alien** — campy sci-fi energy, matter-of-fact naming of wild things, DON'T PANIC
