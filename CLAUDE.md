# CLAUDE.md — Ex_cellence Server

## Shell Commands
Always use tmux-cli for shell commands. Pane layout:
- Pane 1 (main:1.1): Claude (this session)
- Pane 2 (main:1.2): Server
- Pane 3 (main:1.3): iex/scratch terminal

```bash
# Run all tests
tmux-cli send 'cd /home/andrew/projects/ex_cellence_server && mix test' --pane=main:1.3

# Run specific test
tmux-cli send 'cd /home/andrew/projects/ex_cellence_server && mix test test/ex_cellence_server_web/live/members_live_test.exs' --pane=main:1.3

# Format
tmux-cli send 'cd /home/andrew/projects/ex_cellence_server && mix format' --pane=main:1.3

# Start server
tmux-cli send 'cd /home/andrew/projects/ex_cellence_server && mix phx.server' --pane=main:1.2
```

## Project Overview
Standalone Phoenix app providing a web UI for Ex_cellence. Uses guild terminology:
guilds (pre-built agent teams), members (roles), quests (pipelines), lodge (dashboard).
Turnkey via docker-compose.

## Dependencies
- `ex_cellence` (path dep — core library)
- `ex_cellence_dashboard` (path dep — read-only viz components)
- `ex_cellence_ui` (path dep — form components)
- `phoenix`, `phoenix_live_view`, `phoenix_html`
- `salad_ui` — component library
- `ecto_sql`, `postgrex` — database
- `opentelemetry_api`

## Pages
- `/guild-hall` — Browse/install/dissolve guilds (pre-built agent teams)
- `/members` — CRUD members (roles) with RoleForm, lifecycle management
- `/quests` — Quest planner, charter picker, charter installation
- `/evaluate` — Select guild, input text, run against Ollama, live verdicts
- `/lodge` — ReplayViewer, AgentHealth, OutcomeTracker, DriftMonitor, CalibrationChart
- `/` — Redirects to `/lodge` (or `/guild-hall` if no members exist)

## Guild Terminology Map
- Templates → **Charters** (founding docs that define a guild)
- Roles → **Members** (agents in a guild)
- Pipelines → **Quests** (structured missions)
- Dashboard → **Lodge** (home base / monitoring)
- Middleware → **Rituals** (steps members always perform)
- Perspectives → **Disciplines** (areas of expertise)

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

## Gotchas
- Warnings are errors in test
- SaladUI textarea uses `value` attr, not inner content
- Styler formatter plugin — don't fight its rewrites
- TwMerge.Cache is initialized in application.ex (guards against double-creation)
- ex_cellence starts its own Oban + Repo — don't duplicate in our supervision tree
- ex_cellence Repo needs its own DB config pointing to our database
