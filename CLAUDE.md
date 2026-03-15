# CLAUDE.md — ExCortex

## Shell Commands
Always use tmux-cli for shell commands. Pane layout:
- Pane 1 (main:1.1): Claude (this session)
- Pane 2 (main:1.2): Server
- Pane 3 (main:1.3): iex/scratch terminal

```bash
# Run all tests
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test' --pane=main:1.3

# Run specific test
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex_web/live/quests_live_test.exs' --pane=main:1.3

# Format
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix format' --pane=main:1.3

# Start server
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix phx.server' --pane=main:1.2
```

## Git Workflow
- Commit directly to `master` — no feature branches
- Never propose PRs or merges

## Project Overview
Standalone Phoenix app — an AI agent orchestration platform with brain/consciousness vocabulary.
Clusters (agent teams), neurons (agents), thoughts (pipelines), daydreams (runs),
synapses (steps), impulses (step runs), engrams (memories), signals (dashboard cards),
senses (data sources), expressions (notification channels).
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
- `/` → `/cortex` — main dashboard
- `/cortex` — Active thoughts, signals, cluster health, recent memory
- `/neurons` — Cluster and agent management
- `/thoughts` — Pipeline builder and run history
- `/memory` — Engram browser with tiered drill-down (L0/L1/L2)
- `/senses` — Source management, reflexes (templates), streams (feeds), expressions
- `/instinct` — Configuration and settings (LLM providers, API keys, feature flags)
- `/guide` — Documentation / onboarding guide

Legacy routes still work: `/lodge`, `/guild-hall`, `/quests`, `/grimoire`, `/library`, `/town-square`, `/evaluate`, `/settings`

## Brain Vocabulary Map
- Clusters → agent teams (was guilds)
- Neurons → agents/roles (was members)
- Thoughts → pipelines (was quests)
- Daydreams → pipeline runs (was quest runs)
- Synapses → pipeline steps (was steps)
- Impulses → step runs (was step runs)
- Engrams → memories/artifacts (was lore entries) — tiered: L0 impression, L1 recall, L2 full body
- Signals → dashboard cards (was lodge cards)
- Senses → data sources (was sources)
- Reflexes → source templates (was books)
- Streams → pre-configured feeds (was scrolls)
- Expressions → notification channels (was heralds)
- Pathways → agent team definitions (was charters)
- Neuroplasticity → self-improvement loop (was learning loop)

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
- Sense types: git, directory, feed, webhook, url, websocket, obsidian, nextcloud, email, media, github_issues, lodge
- Evaluator module (`ExCortex.Evaluator`) shared between EvaluateLive and Senses
- Webhook endpoint: `POST /api/webhooks/:sense_id` with optional Bearer auth
- Reflexes: source blueprints in `ExCortex.Senses.Reflex`
- Core library uses `Excellence.Charters.*`
- Engrams (`ExCortex.Memory`) store artifacts, notes, and thought outputs — browsed in Memory screen
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
