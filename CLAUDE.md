# CLAUDE.md — ExCortex

## Shell Commands
Always use tmux-cli for shell commands. Pane layout:
- Pane 1 (main:1.1): Claude (this session)
- Pane 2 (main:1.2): Server
- Pane 3 (main:1.3): iex/scratch terminal
- Pane 4 (main:1.4): scratch terminal

```bash
# Run all tests
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test' --pane=main:1.4

# Run specific test
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/signals_test.exs' --pane=main:1.4

# Format
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix format' --pane=main:1.4

# Start server
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix phx.server' --pane=main:1.2
```

## Git Workflow
- Commit directly to `main` — no feature branches
- Never propose PRs or merges

## Project Overview
Standalone Phoenix app — an AI agent orchestration platform with brain/consciousness vocabulary.
Wonder/Muse/Thought (cognitive interactions), Ruminations (multi-step pipelines),
Daydreams (runs), Synapses (steps), Impulses (step runs), Clusters (agent teams),
Neurons (agents), Engrams (memories), Signals (dashboard cards), Senses (data sources),
Expressions (notification channels), Axioms (reference data in the Lexicon).
Turnkey via docker-compose. Has a built-in neuroplasticity loop — the app works on itself.

## Dependencies
- `ex_cellence` (path dep — core library)
- `ex_cellence_dashboard` (path dep — read-only viz components)
- `ex_cellence_ui` (path dep — form components)
- `phoenix`, `phoenix_live_view`, `phoenix_html`
- `salad_ui` — component library
- `ecto_sql`, `postgrex` — database
- `opentelemetry_api`
- `req` — HTTP client (feeds, URLs)
- `file_system` — filesystem watching
- `fresh` — WebSocket client
- `credo` — static analysis (dev/test only)

## Pages
- `/` → `/cortex` — main dashboard with quick-muse input
- `/cortex` — Active ruminations, signals, cluster health, recent memory
- `/wonder` — Pure LLM chat, no data grounding
- `/muse` — Data-grounded chat (RAG over engrams and axioms)
- `/thoughts` — Saved thought templates — browse, re-run, save to memory
- `/neurons` — Cluster and agent management
- `/ruminations` — Multi-step pipeline builder and run history
- `/memory` — Engram browser with tiered drill-down (L0/L1/L2)
- `/senses` — Source management, reflexes (templates), streams (feeds), expressions
- `/instinct` — Configuration and settings (LLM providers, API keys, feature flags)
- `/guide` — Documentation / onboarding guide
- `/evaluate` — Direct evaluation interface
- `/settings` — Settings

## Brain Vocabulary Map
- Wondering → ephemeral LLM chat, no data grounding
- Musing → ephemeral data-grounded chat (RAG)
- Thought → saved single-step query template
- Rumination → multi-step pipeline
- Daydream → a single run of a Rumination
- Synapse → pipeline step
- Impulse → step run
- Cluster → agent team
- Neuron → agent/role
- Pathway → agent team definition
- Engram → memory/artifact — tiered: L0 impression, L1 recall, L2 full body
- Signal → dashboard card
- Sense → data source
- Reflex → source template
- Expression → notification channel
- Axiom → reference dataset (in the Lexicon)
- Cortex → main dashboard
- Instinct → settings/configuration
- Neuroplasticity → self-improvement loop

## LLM Providers
- **Ollama** (local): `ministral-3:8b` (fast), `devstral-small-2:24b` (reliable tool-calling)
- **Claude** (Anthropic): configured via `claude_haiku`, `claude_sonnet`, `claude_opus` model IDs
- Fallback chain: `config :ex_cortex, :model_fallback_chain, ["devstral-small-2:24b"]`
- `gemma3:4b` is installed but breaks on tool-call message format — not in the chain

## Neuroplasticity Pipeline
The app improves itself via two systems seeded by the Dev Team pathway:

**SI: Analyst Sweep** (every 4h) — reads codebase, runs credo, files GitHub issues labeled `self-improvement`

**Neuroplasticity Loop** (triggered by those issues):
PM Triage → Code Writer → Code Reviewer → QA → UX Designer → PM Merge Decision

Re-seed with: `ExCortex.Neuroplasticity.Seed.seed(%{repo: "owner/repo"})`

## Memory System
- Engrams stored with tiered fields: `impression` (L0), `recall` (L1), `body` (L2)
- Categories: `semantic`, `episodic`, `procedural`
- `Memory.query/2` returns tiered results; `load_recall/1` and `load_deep/1` for drill-down
- `Memory.Extractor` auto-creates episodic engrams from completed daydreams
- `Memory.TierGenerator` generates L0/L1 summaries via LLM (async)
- Recall paths track which engrams were accessed during which daydream

## Quality Tools (run_sandbox allowlist)
Only these commands work in `run_sandbox`:
- `mix test [file] [--only tag]`
- `mix credo [--all]`
- `mix excessibility` — accessibility audit of LiveView HTML snapshots
- `mix format [--check-formatted]`
- `mix dialyzer`
- `mix deps.audit`

## Docker
```bash
docker-compose up  # starts TimescaleDB + Ollama + Phoenix app
PORT=4001 docker-compose up  # custom port
```

## Key Patterns
- LiveViews import function components from dashboard/UI packages
- TUI components (`panel`, `status`, `key_hints`, `nav_link`) in `ExCortexWeb.Components.TUI`
- Ollama URL configurable via OLLAMA_URL env var
- Pathways dynamically create role/action modules for evaluation
- PubSub broadcasts evaluation results for live updates
- SaladUI.Button is imported globally via html_helpers
- Senses: DynamicSupervisor-managed workers that poll/push data into clusters for evaluation
- Sense types: git, directory, feed, webhook, url, websocket, obsidian, nextcloud, email, media, github_issues, cortex
- Evaluator module (`ExCortex.Evaluator`) shared between EvaluateLive and Senses
- Webhook endpoint: `POST /api/webhooks/:sense_id` with optional Bearer auth
- Reflexes: source blueprints in `ExCortex.Senses.Reflex`
- Core library uses `Excellence.Charters.*`
- `ExCortex.Muse` is the RAG engine — gathers context from engrams/axioms, calls LLM, persists as Thought
- Engrams (`ExCortex.Memory`) store artifacts, notes, and rumination outputs — browsed in Memory screen
- Axioms (`ExCortex.Lexicon`) store reference datasets — queried via `query_axiom` tool
- `query_memory` tool searches engrams by tags — agents should query it before writing code/tests

## Gotchas
- Warnings are errors in test
- SaladUI textarea uses `value` attr, not inner content
- Styler formatter plugin — don't fight its rewrites
- TwMerge.Cache is initialized in application.ex (guards against double-creation)
- ex_cellence starts its own Oban + Repo — don't duplicate in our supervision tree
- ex_cellence Repo needs its own DB config pointing to our database
- `test/excessibility/html_snapshots/` are auto-generated — always appear modified, not a real problem
- `mix format --check-formatted` will always exit 1 if snapshots were regenerated (false alarm)
- Credo baseline: ~40 pre-existing refactoring opportunities — don't file issues for these
