# CLAUDE.md — ExCalibur

## Shell Commands
Always use tmux-cli for shell commands. Pane layout:
- Pane 1 (main:1.1): Claude (this session)
- Pane 2 (main:1.2): Server
- Pane 3 (main:1.3): iex/scratch terminal

```bash
# Run all tests
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test' --pane=main:1.3

# Run specific test
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur_web/live/quests_live_test.exs' --pane=main:1.3

# Format
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix format' --pane=main:1.3

# Start server
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix phx.server' --pane=main:1.2
```

## Git Workflow
- Commit directly to `master` — no feature branches
- Never propose PRs or merges

## Project Overview
Standalone Phoenix app providing a web UI for Ex_cellence. Uses guild terminology:
guilds (pre-built agent teams), members (roles), quests (pipelines), lodge (dashboard).
Turnkey via docker-compose. Has a built-in self-improvement loop — the app works on itself.

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
- `/` → `/lodge` — redirects to lodge (or `/guild-hall` if no members exist)
- `/lodge` — ReplayViewer, AgentHealth, OutcomeTracker, DriftMonitor, CalibrationChart
- `/town-square` — Charter browser and quest/step installer; run quests manually
- `/guild-hall` — Browse/install/dissolve guilds (pre-built agent teams with charters)
- `/quests` (also `/quest-board`) — Quest planner, charter picker, charter installation
- `/grimoire` — Lore browser; view/create/search lore entries with quest run history
- `/library` — Browse and install source "books" (pre-configured source templates)
- `/evaluate` — Select guild, input text, run against Ollama, live verdicts
- `/settings` — App settings (Ollama URL, API keys, feature flags)
- `/guide` — Documentation / onboarding guide

## Guild Terminology Map
- Templates → **Charters** (founding docs that define a guild) — `@charters`, `Evaluator.charters()`
- Roles → **Members** (agents in a guild)
- Pipelines → **Quests** (structured missions)
- Dashboard → **Lodge** (home base / monitoring)
- Middleware → **Rituals** (steps members always perform)
- Perspectives → **Disciplines** (areas of expertise)

## LLM Providers
- **Ollama** (local): `ministral-3:8b` (fast), `devstral-small-2:24b` (reliable tool-calling)
- **Claude** (Anthropic): configured via `claude_haiku`, `claude_sonnet`, `claude_opus` model IDs
- Fallback chain: `config :ex_calibur, :model_fallback_chain, ["devstral-small-2:24b"]`
- `gemma3:4b` is installed but breaks on tool-call message format — not in the chain

## Self-Improvement Pipeline
The app improves itself via two systems seeded by the Dev Team charter:

**SI: Analyst Sweep** (every 4h) — reads codebase, runs credo, files GitHub issues labeled `self-improvement`

**Self-Improvement Loop** (triggered by those issues):
PM Triage → Code Writer → Code Reviewer → QA → UX Designer → PM Merge Decision

Re-seed with: `ExCalibur.SelfImprovement.QuestSeed.seed(%{repo: "owner/repo"})`

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
- Ollama URL configurable via OLLAMA_URL env var
- Charters dynamically create role/action modules for evaluation
- PubSub broadcasts evaluation results for live updates
- SaladUI.Button is imported globally via html_helpers (CoreComponents button removed)
- Guild terminology is UI-only — internal code uses ResourceDefinition, type: "role", etc.
- Sources: DynamicSupervisor-managed workers that poll/push data into guilds for evaluation
- Source types: git, directory, feed, webhook, url, websocket
- Evaluator module (`ExCalibur.Evaluator`) shared between EvaluateLive and Sources
- Webhook endpoint: `POST /api/webhooks/:source_id` with optional Bearer auth
- Books: source blueprints in `ExCalibur.Sources.Book` — Library for browsing
- Core library uses `Excellence.Charters.*` (was `Excellence.Templates.*`)
- Lore entries (`ExCalibur.Lore`) store artifacts, notes, and quest outputs — browsed in Grimoire
- `query_lore` tool searches lore by tags — agents should query it before writing code/tests

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
