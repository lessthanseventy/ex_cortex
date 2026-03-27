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
- Work on feature branches, PR into `main`
- Branch naming: `feat/<topic>`, `fix/<topic>`, `chore/<topic>`
- CI runs on every PR (GitHub Actions: compile, format, credo, test)
- Branch protection on `main` — PRs required, CI must pass

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
PM Triage → Planning Consensus → Code Writer → Code Reviewer → QA → UX Designer → PM Merge Decision

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

## Dev Workflow
```bash
mise setup              # first-time: deps, db, assets
mise dev                # start services + app with live reload
mise services           # just start background services (db, ollama, observability)
mise stop               # stop background services
```

## Mix Aliases
```bash
mix dev                 # start Phoenix server
mix lint                # compile warnings + format check + credo
mix precommit           # lint + test
mix ci                  # full quality gate
mix release.build       # compile + assets + Burrito release
```

**MIX_ENV notes:** Never set MIX_ENV for dev commands — `mix dev`, `mix test`, `mix format`, `mix credo` all default correctly. Only set `MIX_ENV=prod` for release builds, and the `mix release.build` alias handles that via `mise release`. If running `mix test` in a script, the test alias auto-creates/migrates the test DB.

## Release (Burrito)
The app ships as a standalone binary via Burrito. No Erlang/Elixir needed on the target machine.

```bash
mise release            # builds binary to burrito_out/

# Run it (needs Postgres + Ollama running separately)
DATABASE_URL="ecto://user:pass@host/ex_cortex" \
SECRET_KEY_BASE="$(mix phx.gen.secret)" \
PHX_SERVER=true \
./burrito_out/ex_cortex_linux_x86 start
```

Binaries built for: `linux_x86`, `linux_arm`, `macos_arm`.

API keys can be set via env vars at launch or configured live in `/instinct` (persisted to DB, takes effect without restart).

## Docker (services only)
Docker Compose runs the supporting services, not the app itself:
```bash
docker compose up -d db ollama   # just db + ollama
docker compose up -d             # full stack: db, ollama, jaeger, prometheus, grafana
```

## Key Patterns
- LiveViews import function components from dashboard/UI packages
- TUI components (`panel`, `status`, `key_hints`, `nav_link`) in `ExCortexWeb.Components.TUI`
- Config priority: Settings DB (Instinct UI) → Application env → env vars → defaults
- `Settings.resolve/2` is the single way to read config — LLM modules use it
- Pathways dynamically create role/action modules for evaluation
- PubSub broadcasts evaluation results for live updates
- SaladUI.Button is imported globally via html_helpers
- Senses: DynamicSupervisor-managed workers that poll/push data into clusters for evaluation
- Sense types: git, directory, feed, webhook, url, websocket, obsidian, nextcloud, email, media, github_issues, cortex
- Evaluator module (`ExCortex.Evaluator`) shared between EvaluateLive and Senses
- Webhook endpoint: `POST /api/webhooks/:sense_id` with optional Bearer auth
- Expression reply endpoint: `POST /api/expressions/reply` with `ref` + `content` params
- Reflexes: source blueprints in `ExCortex.Senses.Reflex`
- Core library uses `Excellence.Charters.*`
- `ExCortex.Muse` is the RAG engine — gathers context from engrams/axioms, calls LLM, persists as Thought
- Engrams (`ExCortex.Memory`) store artifacts, notes, and rumination outputs — browsed in Memory screen
- Axioms (`ExCortex.Lexicon`) store reference datasets — queried via `query_axiom` tool
- `query_memory` tool searches engrams by tags — agents should query it before writing code/tests

## Middleware System
- `ExCortex.Ruminations.Middleware` — behaviour with `before_impulse/2`, `after_impulse/3`, `wrap_tool_call/3`
- Synapse schema has `middleware` field (list of module name strings)
- ImpulseRunner resolves middleware from synapse, runs before/after chain around each impulse
- `ExCortex.LLM.ToolExecutor` — shared tool execution for Claude + Ollama, supports middleware wrapping
- Built-in middleware: `ToolErrorHandler`, `UntrustedContentTagger`, `MessageQueueInjector`, `Scratchpad` (opt-in)
- `Scratchpad` middleware: persistent key:value store across impulses within a daydream — models write `SCRATCHPAD:...END_SCRATCHPAD` blocks

## Bidirectional Expressions
- Expressions return `{:ok, external_ref}` on delivery (webhook, slack)
- `expression_correlations` table links outbound messages to daydreams via `external_ref`
- Inbound replies via `POST /api/expressions/reply?ref=<ref>` route to running daydream inbox
- `MessageQueueInjector` middleware drains inbox messages and prepends them to impulse input

## Daydream Dedup
- Rumination schema has `dedup_strategy`: `"none"` (default) or `"concurrent"`
- Daydream schema has `fingerprint` (sha256 of rumination_id + normalized input)
- `concurrent` mode skips creating a new daydream if one with the same fingerprint is already running
- `Ruminations.latest_daydream/1` returns most recent daydream for a rumination (used by pinned signal cards)

## Bounded Pipeline Loops
- Rumination schema has `max_iterations` (default 1 — single pass)
- Synapse schema has `convergence_verdict` (e.g., `"pass"`)
- Runner loops: run all steps, check last verdict against `convergence_verdict`, repeat or stop
- Daydream tracks `iteration_count` and can have status `"converged"`
- Gates still halt immediately regardless of loop iteration

## Keyword-Triggered Ruminations
- Rumination trigger type `"keyword"` with `keyword_patterns` field (list of strings)
- `KeywordTriggerRunner` GenServer subscribes to signals, engrams, and senses PubSub topics
- Case-insensitive substring matching against content; fires `Runner.run/2` on match
- Uses existing dedup to prevent re-triggering

## Markdown Neuron Definitions
- Neurons can be defined as `.md` files in `priv/neurons/` with YAML frontmatter
- `MarkdownLoader.load_all/0` parses frontmatter (id, name, category, lobe, ranks) + body (system_prompt)
- `Builtin.all/0` merges code-defined + markdown-defined neurons (markdown wins on id collision)
- Enables git-diffable neuron prompt changes via neuroplasticity PRs

## Trust Levels
- Sense schema has `trust_level`: `"trusted"` or `"untrusted"` (default)
- Webhook senses always set `trust_level: "untrusted"`
- `UntrustedContentTagger` middleware wraps untrusted input in `<untrusted>` tags with safety warning
- Propagated through: WebhookController → Runner → ImpulseRunner → Middleware.Context.metadata

## Neuroplasticity Loop
- `Loop.retrospect/2` is memory-informed — queries past run engrams and previous proposals before generating new ones
- `ProposalExecutor` auto-applies approved roster/schedule changes to synapses; prompt changes flagged for manual review
- `ProposalPolicy` evaluates proposals against auto-approve/reject rules from Settings (Instinct UI)
- Policies configurable via `:proposal_policies` setting — list of rule maps with type/tool/trust matchers
- Trust scores now bidirectional: decay (×0.97) on disagreement, boost (×1.005) on agreement
- Trust-weighted effective confidence in right-hemisphere consensus: `raw_confidence × trust_score`

## ImpulseRunner Architecture
- Main module (473 lines) at `lib/ex_cortex/ruminations/impulse_runner.ex`
- Submodules: `Consensus` (verdict parsing/aggregation), `Artifact` (generation/signal posting), `Reflect` (tool-assisted retry), `Escalation` (rank ladder)
- `with_middleware/4` wraps all run clauses — eliminates boilerplate

## Sense Feedback Loop
- `ExCortex.Senses.Feedback` GenServer subscribes to daydream completions
- Analyzes verdict patterns for source-triggered ruminations
- 80%+ pass rate → slow down polling (×1.5 interval)
- 60%+ fail rate → speed up polling (×0.75 interval)
- Respects min/max bounds (30s–1h)

## Pathway Eval Harness
- `mix eval_pathway` runs golden-input evaluations against synapses
- Eval sets stored as engrams with category "eval" and tagged with synapse name
- Reports per-synapse pass rates and overall accuracy
- Flags: `--synapse "Name"` to filter, `--tag domain` to scope

## Muse Context Intelligence
- `ExCortex.Muse.Classifier` classifies questions via ministral-3:8b before context gathering
- Determines providers, time range, obsidian mode/sections, and search terms
- Drives both context provider selection AND tool selection (curated per question)
- Obsidian provider supports `daily_range` mode — reads last N daily notes with section filtering
- `extract_sections/2` pulls specific callout blocks from note content

## Code Style
- In LiveView modules: group all `handle_event` clauses together, then all private helpers at the bottom. Never interleave `defp` functions between `handle_event` clauses — it causes clause grouping warnings.
- Private functions (`defp`) go at the bottom of the module, after all public functions and callbacks.

## Gotchas
- Warnings are errors in test and dev
- SaladUI textarea uses `value` attr, not inner content
- Styler formatter plugin — don't fight its rewrites
- TwMerge.Cache is initialized in application.ex (guards against double-creation)
- ex_cellence starts its own Oban + Repo — don't duplicate in our supervision tree
- ex_cellence Repo needs its own DB config pointing to our database
- `test/excessibility/html_snapshots/` are auto-generated — always appear modified, not a real problem
- `mix format --check-formatted` will always exit 1 if snapshots were regenerated (false alarm)
- Credo must pass clean: `mix credo --all` should report zero issues
