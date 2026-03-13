# ExCalibur

A Phoenix web application for running multi-agent AI evaluation pipelines, structured autonomous workflows (quests), and continuous self-improvement. Organizes AI agents into named **guilds**, gives them **quests** (multi-step pipelines with tool calling), and lets them evaluate content, write code, file issues, and improve the system itself — all under a human-in-the-loop approval model.

---

## Contents

- [Concepts](#concepts)
- [Architecture](#architecture)
- [Self-Improvement Loop](#self-improvement-loop)
- [Pages](#pages)
- [Tools](#tools)
- [Sources](#sources)
- [Running It](#running-it)
- [Configuration](#configuration)
- [Observability](#observability)
- [Development](#development)

---

## Concepts

### Guilds and Members

A **guild** is a multi-agent team defined by a **charter** — a data structure specifying which roles are in the team, what models they use, and how they reach decisions.

A **member** (internally: role) is an individual agent with a system prompt, a rank (apprentice / journeyman / master), and one or more **perspectives** — model variants that evaluate from different angles simultaneously.

Built-in guilds: Code Review, Content Moderation, Accessibility Review, Risk Assessment, Performance Audit, Dependency Audit, Incident Triage, Contract Review, and the Dev Team (self-improvement).

### Quests and Steps

A **quest** is a multi-step pipeline. Each **step** runs a roster of members against an input and produces a structured result. Steps chain together — each step's output is prepended to the next step's input as a formatted handoff block.

Step options:
- **Verdict output** — members vote pass/warn/fail with confidence and reasoning
- **Freeform output** — members write artifact text (summaries, code, analysis)
- **Gate flag** — halt the quest if the verdict is fail
- **Loop tools** — list of tools agents may call during the step
- **Dangerous tool mode** — execute / intercept / dry_run for dangerous tool calls
- **Max iterations** — circuit breaker on the agent tool-calling loop

### Lore

**Lore** entries are knowledge artifacts produced by quest runs: summaries, findings, decisions. Tagged and stored for retrieval by future quests via the `query_lore` tool. Browsed in the Grimoire.

### Sources and Books

**Sources** are data pipeline workers — they poll or receive data and feed it into guild evaluation. A **Book** is a pre-configured source template. Install a Book from the Library to create an active Source managed in Stacks.

Source types: `git`, `directory`, `feed`, `webhook`, `url`, `websocket`, `github_issues`, `obsidian`, `nextcloud`, `email`, `media`, `lodge`.

### Proposals

When an agent tries to call a write or dangerous tool, instead of executing it immediately the system creates a **Proposal** — a record with the action description and suggested parameters. Proposals appear in the Lodge for human review and can be approved or rejected.

---

## Architecture

### Evaluation Pipeline

The simple evaluation path (Evaluate page, no tool calling):

```mermaid
flowchart TD
    Input[User Input Text] --> E[Evaluator.evaluate]
    E --> Guild{Current guild?}
    Guild -- none --> Err[error: no guild installed]
    Guild -- found --> Build[Build dynamic Role modules\nfrom charter metadata]
    Build --> Orch[Orchestrator.evaluate]
    Orch --> FanOut[Fan out to role variants\nin parallel]
    FanOut --> LLM1[Member A\nalpha perspective]
    FanOut --> LLM2[Member B\nbeta perspective]
    FanOut --> LLM3[Member C\nstrict perspective]
    LLM1 & LLM2 & LLM3 --> Consensus[Per-role consensus]
    Consensus --> Cross[Cross-role decision\nstrategy: majority / unanimous / veto]
    Cross --> Verdict[Verdict: approve / reject]
    Verdict --> PubSub[PubSub broadcast]
    PubSub --> Lodge[Lodge updates live]
```

### Quest Pipeline

The full quest path — multi-step with tool-calling agents:

```mermaid
flowchart TD
    Trigger[Trigger: manual / scheduled / source event] --> QR[QuestRunner.run]

    subgraph Per Step
        SR[StepRunner.run] --> CTX[Assemble context\nlore, git diffs, files]
        CTX --> Roster[Run roster members\nvia Ollama or Claude]
        Roster --> Tools{Tool call?}
        Tools -- safe --> Exec[Execute immediately]
        Tools -- write / dangerous --> Propose[Create Proposal]
        Exec --> Roster
        Propose --> Roster
        Roster --> Result[Step result]
    end

    QR --> SR
    Result --> Gate{Gated step?}
    Gate -- fail verdict --> Halt[Quest halted]
    Gate -- pass / not gated --> Handoff[Handoff block\nprepended to next input]
    Handoff --> SR
    Result --> Run[QuestRun record updated]
    Run --> PubSub2[PubSub broadcast]
```

### Supervision Tree

```mermaid
graph TD
    App[ExCalibur.Application] --> Repo[ExCalibur.Repo]
    App --> Oban[Oban]
    App --> PubSub[ExCalibur.PubSub]
    App --> SourceSupervisor[Sources.SourceSupervisor\nDynamicSupervisor]
    App --> Debouncer[QuestDebouncer]
    App --> Bridge[PubSubBridge]
    App --> Web[ExCaliburWeb.Endpoint]
    App --> Sched[ScheduledQuestRunner]
    App --> LoreTrigger[LoreTriggerRunner]
    App --> LodgeTrigger[LodgeTriggerRunner]
    SourceSupervisor --> W1[SourceWorker A]
    SourceSupervisor --> W2[SourceWorker B]
    SourceSupervisor --> Wn[...]
```

---

## Self-Improvement Loop

ExCalibur includes a Dev Team guild that autonomously improves itself. Two interlocking loops:

```mermaid
flowchart LR
    subgraph Analyst Sweep - every 4 hours
        AS1[Codebase Health Scan\nmix credo + targeted reads]
        AS2[Opportunity Scan\nproduct lens]
        AS3[Backlog Synthesis\nPM approves shortlist]
        AS4[Issue Filing\ncreate GitHub issues]
        AS1 --> AS2 --> AS3 --> AS4
    end

    subgraph Self-Improvement Loop - per issue
        SI1[PM Triage\naccept or reject]
        SI2[Code Writer\nworktree + implement]
        SI3[Code Reviewer\ngate: fail halts quest]
        SI4[QA\ngate: fail halts quest]
        SI5[PM Merge Decision\nauto-merge or escalate]
        SI1 --> SI2 --> SI3 --> SI4 --> SI5
    end

    AS4 -- labeled self-improvement --> SI1
    SI5 -- approved --> GH[GitHub PR merged]
    SI5 -- escalated --> Lodge[Lodge proposal\nfor human review]
```

**Guardrails:**
- Circuit breaker on tool-calling loops — skips tools after 3 consecutive empty results
- Verdict gates — Code Reviewer and QA steps halt the quest on fail
- Dangerous tool interception — `create_github_issue`, `merge_pr`, etc. produce Proposals
- Rollback — failed freeform steps with write tools stash and restore working tree

Seed the SI pipeline: `ExCalibur.SelfImprovement.QuestSeed.seed(%{repo: "owner/repo"})`

---

## Pages

| Route | Page | Purpose |
|---|---|---|
| `/lodge` | Lodge | Dashboard — verdict history, agent health, drift monitor |
| `/town-square` | Town Square | Charter browser — install roles from a charter |
| `/guild-hall` | Guild Hall | Browse and install complete guilds |
| `/quests` | Quests | Design and run multi-step quest pipelines |
| `/grimoire` | Grimoire | Lore browser — search and view knowledge artifacts |
| `/library` | Library | Browse Books and Scrolls, install as sources |
| `/stacks` | Stacks | Manage active sources — pause, resume, delete |
| `/evaluate` | Evaluate | One-shot guild evaluation with live verdict feed |
| `/settings` | Settings | App config — Ollama URL, API keys, default repo |
| `/guide` | Guide | Docs and onboarding |

`/` redirects to `/lodge` (or `/guild-hall` if no members are installed).

---

## Tools

Tools are tiered by risk. Steps declare which tools agents may call via `loop_tools`.

### Safe — execute immediately

| Tool | Description |
|---|---|
| `query_lore` | Search lore store by tags |
| `read_file` | Read a local file |
| `list_files` | List directory contents |
| `fetch_url` | Fetch web content |
| `web_search` | Web search |
| `web_fetch` | Full page fetch |
| `search_github` | Search GitHub issues/PRs/repos |
| `read_github_issue` | Fetch issue detail |
| `list_github_notifications` | GitHub notification inbox |
| `search_obsidian` | Obsidian vault search |
| `read_obsidian` | Read a note |
| `read_obsidian_frontmatter` | Extract note metadata |
| `search_obsidian_content` | Full-text vault search |
| `search_email` | Search email |
| `read_email` | Read a message |
| `read_pdf` | Extract PDF text |
| `convert_document` | Document format conversion |
| `describe_image` | Vision API description |
| `read_image_text` | OCR |
| `analyze_video` | Video analysis |
| `transcribe_audio` | Speech to text |
| `jq_query` | JSON processing |
| `query_jaeger` | Query distributed traces |
| `run_sandbox` | Allowlisted mix commands: `test`, `credo`, `format`, `excessibility`, `deps.audit` |
| `search_nextcloud` | Nextcloud file search |
| `read_nextcloud` | Read a Nextcloud file |
| `read_nextcloud_notes` | Read Nextcloud Notes |
| `query_dictionary` | Word definitions |

### Write — create Proposal

| Tool | Description |
|---|---|
| `write_file` | Create or overwrite a file |
| `edit_file` | Targeted line-level edit |
| `git_commit` | Commit staged changes |
| `git_push` | Push to remote |
| `open_pr` | Open or draft a pull request |
| `create_obsidian_note` | Create or append a note |
| `daily_obsidian` | Daily journal entry |
| `download_media` | Cache a media file |
| `extract_audio` | Extract audio from video |
| `extract_frames` | Extract video frames |
| `setup_worktree` | Create a git worktree |
| `write_nextcloud` | Write a Nextcloud file |
| `create_nextcloud_note` | Create a Nextcloud note |
| `nextcloud_calendar` | Create a calendar event |

### Dangerous — create Proposal

| Tool | Description |
|---|---|
| `create_github_issue` | File a GitHub issue |
| `comment_github` | Add a comment |
| `merge_pr` | Merge a pull request |
| `close_issue` | Close an issue |
| `git_pull` | Fetch from origin |
| `send_email` | Send an email |
| `run_quest` | Trigger another quest |
| `restart_app` | Restart the Phoenix server |
| `nextcloud_talk` | Send a Nextcloud Talk message |

---

## Sources

Sources run as supervised GenServer workers under `ExCalibur.Sources.SourceSupervisor`.

| Type | Behavior |
|---|---|
| `git` | Polls a Git repo for new commits; generates per-file diffs |
| `directory` | Watches a local directory for file changes |
| `feed` | Polls RSS/Atom feeds |
| `webhook` | Receives `POST /api/webhooks/:source_id` (optional Bearer auth) |
| `url` | Polls a URL and detects content changes |
| `websocket` | Connects to a WebSocket stream |
| `github_issues` | Watches GitHub issues with a label filter |
| `obsidian` | Watches an Obsidian vault for new/changed notes |
| `nextcloud` | Polls Nextcloud Activity API |
| `email` | Checks an email inbox |
| `media` | Processes media files (video/audio) |
| `lodge` | Internal metrics stream |

---

## Running It

### Docker Compose (recommended)

```bash
docker compose up
```

| Service | URL | Notes |
|---|---|---|
| Phoenix app | http://localhost:4001 | Live reload enabled |
| Jaeger UI | http://localhost:16686 | Trace browser |
| Grafana | http://localhost:3000 | Anonymous login, auto-provisioned |
| Prometheus | http://localhost:9090 | |
| Nextcloud | http://localhost:8080 | admin / admin — optional |

Database: TimescaleDB/PostgreSQL 16 on port 5433.

Custom port: `PORT=4001 docker compose up`

### Local Dev (deps via Docker)

```bash
# Start only external deps
docker compose up db ollama jaeger

# Install Elixir deps, create and migrate DB
mix setup

# Start the server
mix phx.server
```

Visit http://localhost:4000.

### First Run

```bash
# Full DB reset + install Dev Team guild
mix ecto.fresh
```

Then:
1. Go to **Guild Hall** and install a guild
2. Go to **Quests** to design pipelines
3. Go to **Evaluate** to run a quick one-shot evaluation
4. Go to **Lodge** to monitor results

---

## Configuration

### Environment Variables

```bash
# LLM
OLLAMA_URL=http://localhost:11434       # default
OLLAMA_API_KEY=                         # optional

# Observability
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

# Nextcloud (optional)
NEXTCLOUD_URL=http://localhost:8080
NEXTCLOUD_USER=admin
NEXTCLOUD_PASSWORD=admin

# Production
SECRET_KEY_BASE=...                     # mix phx.gen.secret
PHX_HOST=your-domain.com
PORT=4000
DATABASE_URL=ecto://user:pass@host/db
```

### Runtime Settings

Editable at `/settings` and stored in the database:

- Ollama URL and API key
- Default GitHub repo (`owner/repo`) used by GitHub tools
- Claude API key (for steps using Claude models)
- Nextcloud credentials
- Banner text

### Model Fallback Chain

If the primary model is unavailable, steps fall back:

```elixir
config :ex_calibur, :model_fallback_chain, ["devstral-small-2:24b"]
```

### Production Build

```bash
docker build -t ex-calibur -f Dockerfile .
```

Required env: `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `OLLAMA_URL`.

---

## Observability

All HTTP requests, DB queries, and LLM calls emit OpenTelemetry traces.

```mermaid
flowchart LR
    App[ExCalibur] -->|OTLP HTTP| Collector[OTel Collector]
    Collector -->|OTLP gRPC| Jaeger
    Collector --> Prometheus
    Prometheus --> Grafana
```

The `query_jaeger` tool lets quest steps inspect traces from previous runs — useful for the self-improvement loop to validate that changes improved performance.

---

## Development

### Test Commands

```bash
mix test                              # all tests
mix test test/path/file_test.exs      # specific file
mix test --only focus                 # focused tests
```

### Code Quality

```bash
mix credo                             # static analysis
mix format                            # formatting (Styler plugin rewrites aggressively)
mix deps.audit                        # security
mix excessibility                     # LiveView accessibility snapshot tests
mix precommit                         # compile + unlock + format + test
```

### Key Patterns

**Warnings are errors in test.** Prefix unused variables with `_`, don't delete them.

**Styler rewrites code on `mix format`.** Don't fight it.

**SaladUI.Button is imported globally** via `html_helpers`. Don't use CoreComponents' button.

**PubSub topics:**

| Topic | When |
|---|---|
| `"evaluation:results"` | New evaluation verdict |
| `"quest_runs"` | Quest run status change |
| `"lore"` | New lore entry |
| `"lodge"` | Lodge card update |
| `"sources"` | Source status change |

### Project Structure

```
lib/
  ex_calibur/
    application.ex              # Supervision tree
    evaluator.ex                # Guild evaluation (one-shot path)
    quest_runner.ex             # Multi-step quest execution
    step_runner.ex              # Single step + tool calling loop
    board.ex                    # Quest board state
    settings.ex                 # Runtime settings

    charters/                   # Guild definitions (20+)
    self_improvement/           # SI quest seed
    sources/                    # Source workers and type modules
    tools/                      # Tool implementations (50+)
    llm/                        # Ollama and Claude clients
    quests/                     # Ecto schemas: Quest, Step, QuestRun, Proposal
    lore/                       # Lore Ecto schema

  ex_calibur_web/
    live/                       # LiveView pages
    router.ex
    endpoint.ex

  ex_calibur_ui/
    components/                 # Shared form components

docker-compose.yml
Dockerfile / Dockerfile.dev
priv/repo/migrations/
```

### Guild Terminology vs Internal Names

| UI | Internal |
|---|---|
| Guild | Charter |
| Member | Role |
| Quest | Pipeline |
| Lodge | Dashboard |
| Grimoire | Lore browser |
| Book | Source template |
| Scroll | Pre-configured feed source |
| Ritual | Middleware (always-on behavior) |
| Discipline | Perspective (model variant) |
