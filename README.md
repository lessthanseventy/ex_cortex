<p align="center">
  <img src="priv/static/images/logo.svg" width="128" alt="ExCortex logo" />
</p>

<h1 align="center">ExCortex</h1>

<p align="center">
  <strong>A self-improving AI agent platform that runs entirely on your machine.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Elixir-1.15+-4B275F?logo=elixir&logoColor=white" alt="Elixir 1.15+" />
  <img src="https://img.shields.io/badge/Phoenix-1.8-FD4F00?logo=phoenixframework&logoColor=white" alt="Phoenix 1.8" />
  <img src="https://img.shields.io/badge/LiveView-1.1-FD4F00" alt="LiveView 1.1" />
  <img src="https://img.shields.io/badge/Ollama-local_LLMs-333333?logo=ollama" alt="Ollama" />
  <img src="https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white" alt="PostgreSQL" />
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="MIT License" />
</p>

---

ExCortex is an AI agent orchestration platform with a biological nervous system metaphor baked into every layer. You define teams of agents (clusters of neurons), wire them to your data sources (senses), and they work autonomously — reviewing code, triaging incidents, summarizing feeds, filing bugs, and then improving the system itself.

No cloud. No SaaS. No data leaving your network. Just local LLMs, a Postgres database, and a Phoenix LiveView UI that updates in real time as your agents think.

**The headline feature:** ExCortex includes a Dev Team that reads its own GitHub issues, writes fixes, reviews its own code, runs the test suite, and merges approved changes. It literally gets better while you sleep.

---

## Table of Contents

- [Neuroplasticity — Self-Improvement](#neuroplasticity--self-improvement)
- [Multi-Agent Clusters](#multi-agent-clusters)
- [Data Sources — Senses](#data-sources--senses)
- [Chat — Wonder & Muse](#chat--wonder--muse)
- [Pipelines — Ruminations](#pipelines--ruminations)
- [Memory — Engrams](#memory--engrams)
- [54 Agent Tools](#54-agent-tools)
- [Architecture](#architecture)
- [Brain Vocabulary](#brain-vocabulary)
- [Pages](#pages)
- [Quickstart](#quickstart)
- [Observability](#observability)
- [Deployment](#deployment)
- [Configuration](#configuration)
- [Development](#development)
- [Tech Stack](#tech-stack)

---

## Neuroplasticity — Self-Improvement

This is the thing that makes ExCortex different. The system improves itself at three levels — not just its code, but its own configuration, prompts, and trust in its agents.

### Level 1: Feedback — Trust Scoring

Every time a step runs, each neuron's individual verdict is compared against the team consensus. Neurons that consistently contradict the group have their trust score decayed (`×0.97`, compounding). Over time, this surfaces which agents are reliable and which are drifting — informing roster changes and escalation decisions. This happens automatically, no human input needed.

### Level 2: Configuration — Retrospective Proposals

After every step completes, an async retrospective runs in the background. A lightweight LLM reviews the step definition alongside the actual run trace — who ran, what they said, how confident they were — and proposes up to 3 concrete tuning changes:

| Proposal Type | What It Tunes |
|---|---|
| `roster_change` | Swap neurons, change team composition or consensus strategy |
| `schedule_change` | Adjust polling intervals or cron schedules |
| `prompt_change` | Tweak system prompts, instructions, or reasoning strategies |
| `other` | Timeouts, thresholds, model assignments, escalation rules |

These proposals land on the Cortex dashboard for you to approve or reject. The system suggests; you decide.

Every synapse (step) has its own tunable knobs: escalation thresholds, reflection confidence floors, model selection, tool iteration limits, dangerous tool handling mode, context providers, and scheduling. Neurons carry their own config — rank, model, strategy, system prompt. Senses have polling intervals. All of it is hot-reloadable through the Instinct UI — no restart required.

### Level 3: Code — The Self-Improvement Loop

For changes that go beyond configuration, ExCortex can modify its own source code.

The **Analyst Sweep** runs every 4 hours. Three steps — a Code Auditor runs `mix credo` and `mix test`, a Product Analyst identifies feature opportunities, and a Backlog Manager cross-references existing GitHub issues and files 3–5 new ones labeled `self-improvement`.

The **Self-Improvement Loop** picks up those issues:

```
Issue filed → PM Triage → Code Writer → Code Reviewer → QA → UX Review → PM Merge Decision
```

The Code Writer works in an isolated git worktree — never touches the main repo directly. It reads files, makes changes, runs `mix test` and `mix credo`, commits, and opens a real PR. The Code Reviewer and QA gate the pipeline — if tests fail, nothing merges. The PM makes the final call: low-risk changes auto-merge, anything touching core logic creates a Proposal for you.

Re-seed the pipeline anytime:

```elixir
ExCortex.Neuroplasticity.Seed.seed(%{repo: "owner/repo"})
```

### The Full Picture

```
Automatic:  Trust scores decay on every run → surfaces unreliable neurons
Suggested:  Retrospective proposals after every step → prompt/roster/schedule tuning
Applied:    Self-improvement loop every 4h → code changes via PR
```

All three layers feed the same Cortex dashboard. You see trust trends, pending proposals, and open PRs in one place. The system gets better continuously — you stay in control of what actually changes.

---

## Multi-Agent Clusters

Clusters are teams of neurons (agents) with distinct perspectives that evaluate inputs independently, then vote on a consensus verdict. Each neuron sees the same content through a different lens — security, style, architecture, compliance — and the final verdict aggregates their confidence scores.

### Built-in Pathways

Pathways are cluster blueprints that seed a full team of neurons in one step. ExCortex ships with 20+ pre-built pathways:

| Pathway | What It Does |
|---|---|
| **Code Review** | Security auditing, style review, architecture analysis |
| **Content Moderation** | Safety screening, bias detection, policy compliance |
| **Accessibility Review** | WCAG compliance, assistive tech compatibility |
| **Risk Assessment** | Risk identification, compliance checks, fraud signals |
| **Performance Audit** | Bottleneck detection, scalability analysis |
| **Dependency Audit** | Vulnerability scanning, version currency |
| **Incident Triage** | Severity classification, response suggestions |
| **Contract Review** | Legal document analysis, risk flagging |
| **Dev Team** | The self-improvement cluster — code, review, test, merge |

Seed pathways from the Genesis page. Each pathway creates a cluster with its neurons in the database and wires them to the evaluation pipeline. Or build your own — pathways are just Elixir modules with metadata functions. There's nothing special about the built-in ones.

---

## Data Sources — Senses

Senses are supervised workers that watch external data and feed it into your clusters for evaluation. They poll, push, or stream — whatever the source needs.

| Sense | What It Watches |
|---|---|
| `git` | Commits in a local repository |
| `directory` | File changes in a directory tree |
| `feed` | RSS / Atom feeds |
| `webhook` | Incoming `POST /api/webhooks/:id` requests |
| `url` | Content changes at a URL (polling) |
| `websocket` | Live WebSocket streams |
| `github_issues` | GitHub issues matching a label filter |
| `obsidian` | New or changed notes in an Obsidian vault |
| `nextcloud` | Nextcloud activity feed and files |
| `email` | Email inbox monitoring |
| `media` | Video/audio files for transcription and analysis |

Each sense type has a **Reflex** — a source template that pre-configures common setups. Point a git sense at your repo, wire it to the Code Review cluster, and every new commit gets a multi-agent review in ~30 seconds.

The webhook sense accepts optional Bearer token authentication. The email sense handles both standard and epoch-timestamp formats.

---

## Chat — Wonder & Muse

Two conversational interfaces for different needs:

**Wonder** (`/wonder`) — Pure LLM chat. No context retrieval, no grounding. Just you and the model, thinking out loud.

**Muse** (`/muse`) — Data-grounded RAG chat. Muse queries your engram store and axiom datasets, assembles relevant context, calls the LLM with that context, and persists the result as a Thought. When you ask Muse a question, it's answering from *your* knowledge base.

Both support all configured LLM providers (Ollama local models, Claude via Anthropic API) and fall back through the model chain automatically.

---

## Pipelines — Ruminations

Ruminations are multi-step pipelines where each step (synapse) is an evaluation by a team of agents with access to tools. A single run of a rumination is called a **daydream**, and each step execution is an **impulse**.

A synapse can:
- Read files, search GitHub, query your memory store
- Run sandboxed shell commands (`mix test`, `mix credo`, `mix format`)
- Write files, create commits, open pull requests
- File issues, send emails, post to Nextcloud Talk
- Trigger other ruminations (recursive pipelines)

Each tool call that modifies the outside world goes through the **Proposal** system — an approval record you can review, approve, or reject from the dashboard. Safe tools (read, search, fetch) execute immediately. Write and dangerous tools wait for approval.

Build and manage ruminations from the pipeline builder at `/ruminations`.

---

## Memory — Engrams

ExCortex has a tiered memory system inspired by how biological memory consolidation works.

### Three Tiers

| Tier | Name | What It Stores |
|---|---|---|
| **L0** | Impression | One-line summary — fast to scan, cheap to retrieve |
| **L1** | Recall | Paragraph-level detail — key facts and context |
| **L2** | Body | Full content — the complete artifact |

### Categories

- **Semantic** — Facts, definitions, reference knowledge
- **Episodic** — Events, conversations, run outputs
- **Procedural** — How-to knowledge, patterns, processes

### How It Works

`Memory.query/2` returns L0 impressions by default — fast, scannable results. Call `load_recall/1` to expand to L1 detail, or `load_deep/1` for the full L2 body. This keeps queries fast while letting you drill down when you need depth.

The **Memory Extractor** automatically creates episodic engrams from completed daydreams. The **Tier Generator** uses an LLM to produce L0/L1 summaries asynchronously — you get full-text L2 immediately and the summaries populate in the background.

**Recall Paths** track which engrams were accessed during which daydream, giving you an audit trail of what knowledge each agent run consumed.

Browse and search the full engram store at `/memory`.

---

## 54 Agent Tools

Agents call tools during evaluation steps. Every tool is classified by risk level:

### Safe — Execute Immediately

`read_file` · `list_files` · `fetch_url` · `web_search` · `query_lore` · `search_github` · `read_github_issue` · `search_obsidian` · `read_obsidian` · `search_email` · `read_email` · `read_pdf` · `convert_document` · `describe_image` · `read_image_text` · `transcribe_audio` · `analyze_video` · `jq_query` · `run_sandbox` · `query_jaeger` · `search_nextcloud` · `read_nextcloud` · `read_nextcloud_notes` · `query_dictionary`

### Write — Create Proposal

`write_file` · `edit_file` · `git_commit` · `git_push` · `open_pr` · `create_obsidian_note` · `setup_worktree` · `write_nextcloud` · `create_nextcloud_note` · `nextcloud_calendar`

### Dangerous — Create Proposal

`create_github_issue` · `comment_github` · `merge_pr` · `close_issue` · `git_pull` · `send_email` · `run_quest` · `restart_app` · `nextcloud_talk`

The `run_sandbox` tool only allows explicitly allowlisted commands: `mix test`, `mix credo`, `mix excessibility`, `mix format`, `mix dialyzer`, `mix deps.audit`.

---

## Architecture

### Evaluation Flow

```mermaid
flowchart TD
    Sources["Senses
    git · feed · webhook · email
    github · obsidian · nextcloud
    directory · url · websocket · media"]

    Sources --> Input

    subgraph Eval ["Cluster Evaluation"]
        Input --> NeuronA["Neuron A
        alpha perspective"]
        Input --> NeuronB["Neuron B
        beta perspective"]
        Input --> NeuronC["Neuron C
        strict perspective"]
        NeuronA & NeuronB & NeuronC --> Consensus["Consensus
        vote → verdict + confidence"]
    end

    Eval --> Cortex["Cortex Dashboard
    signals · proposals · history"]
    Cortex --> Memory["Engram Store
    L0 · L1 · L2 memory tiers"]
    Memory --> Eval
```

### Tool Safety Model

```mermaid
flowchart TD
    Agent["Agent"] --> ToolCall{"Tool call"}
    ToolCall -- "safe: read / search / fetch" --> Exec["Execute immediately"]
    ToolCall -- "write: file / commit / PR" --> Proposal["Create Proposal"]
    ToolCall -- "dangerous: issue / email / merge" --> Proposal
    Exec --> Result["Result back to agent"]
    Proposal --> Dashboard["Dashboard: awaiting approval"]
    Dashboard -- "approved" --> Exec
    Dashboard -- "rejected" --> Denied["Denied — agent notified"]
```

### Neuroplasticity Loop

```mermaid
flowchart LR
    Sweep["Analyst Sweep
    every 4h"] --> Issues["GitHub Issues
    labeled self-improvement"]
    Issues --> PM["PM Triage"]
    PM --> Writer["Code Writer
    read · write · test"]
    Writer --> Reviewer["Code Reviewer
    diff · credo · test"]
    Reviewer --> QA["QA
    full test suite"]
    QA --> UX["UX Review"]
    UX --> Merge{"PM Decision"}
    Merge -- "low risk" --> Auto["Auto-merge"]
    Merge -- "high risk" --> Propose["Proposal for human review"]
```

---

## Brain Vocabulary

ExCortex uses a biological nervous system metaphor throughout. Here's the full map:

| Term | Meaning |
|---|---|
| **Cortex** | Main dashboard — the brain's control center |
| **Neuron** | An individual agent/role |
| **Cluster** | A team of neurons working together |
| **Pathway** | A cluster's team definition and configuration |
| **Synapse** | A pipeline step — the connection between neurons |
| **Impulse** | A single execution of a synapse |
| **Rumination** | A multi-step pipeline — deep, structured thinking |
| **Daydream** | One run of a rumination |
| **Engram** | A memory artifact — tiered (L0/L1/L2) |
| **Signal** | A dashboard card — a notification from the nervous system |
| **Sense** | A data source — the platform's sensory input |
| **Reflex** | A source template — automatic response to stimulus |
| **Expression** | A notification channel — how the brain communicates outward |
| **Axiom** | Reference data in the Lexicon — foundational knowledge |
| **Wonder** | Ephemeral LLM chat — free association |
| **Muse** | Data-grounded RAG chat — informed thinking |
| **Thought** | A saved query template — a crystallized idea |
| **Instinct** | Settings and configuration — base behaviors |
| **Neuroplasticity** | The self-improvement loop — the brain rewiring itself |
| **Genesis** | Pathway seeding — creating new clusters of neurons |

---

## Pages

| Route | Page | Purpose |
|---|---|---|
| `/` `/cortex` | **Cortex** | Live dashboard — signals, active ruminations, cluster health, recent memory |
| `/wonder` | **Wonder** | Pure LLM chat, no data grounding |
| `/muse` | **Muse** | RAG chat over engrams and axioms |
| `/thoughts` | **Thoughts** | Saved thought templates — browse, re-run, save to memory |
| `/neurons` | **Neurons** | Cluster and agent management |
| `/ruminations` | **Ruminations** | Pipeline builder and run history |
| `/genesis` | **Genesis** | Pathway seeding — install clusters from the pathway library |
| `/memory` | **Memory** | Engram browser with tiered drill-down |
| `/senses` | **Senses** | Source management, reflexes, feeds, expressions |
| `/evaluate` | **Evaluate** | Direct evaluation interface |
| `/instinct` | **Instinct** | Configuration — LLM providers, API keys, feature flags |
| `/settings` | **Settings** | Application settings |
| `/guide` | **Guide** | Documentation and onboarding |

---

## Quickstart

### One command (Docker)

```bash
docker compose up
```

That's it. Starts ExCortex, PostgreSQL, Ollama, Jaeger, Prometheus, and Grafana.

| Service | URL |
|---|---|
| **ExCortex** | http://localhost:4001 |
| **Jaeger** (traces) | http://localhost:16686 |
| **Grafana** (metrics) | http://localhost:3000 |
| **Nextcloud** (optional) | http://localhost:8080 |

Custom port: `PORT=4002 docker compose up`

### First run

```bash
# Reset DB and seed the Dev Team pathway
mix ecto.fresh
```

Then open Genesis and seed whichever pathways you need.

### Local dev (without Docker for the app)

```bash
docker compose up db ollama jaeger   # just the dependencies
mix setup                            # deps, db, assets
mix phx.server                       # start ExCortex
```

### With mise

```bash
mise setup    # first-time: deps, db, assets
mise dev      # start services + app with live reload
mise stop     # stop background services
```

---

## Observability

Every request, database query, and LLM call emits **OpenTelemetry** traces. The Docker Compose stack includes a full observability pipeline:

```
App → OpenTelemetry Collector → Jaeger (traces) + Prometheus (metrics) → Grafana (dashboards)
```

Agents can query their own traces using the `query_jaeger` tool. The self-improvement loop uses this to verify that a code change actually made things faster — not just that the tests pass.

| Component | Port | Purpose |
|---|---|---|
| OpenTelemetry Collector | 4317/4318 | Receives traces and metrics from the app |
| Jaeger | 16686 | Distributed trace visualization |
| Prometheus | 9090 | Metrics storage and querying |
| Grafana | 3000 | Dashboards and alerting |

---

## Deployment

### Standalone Binary (Burrito)

ExCortex ships as a self-contained binary via [Burrito](https://github.com/burrito-elixir/burrito). No Erlang or Elixir installation required on the target machine.

```bash
mix release.build
```

Builds for: `linux_x86`, `linux_arm`, `macos_arm`

Run it:

```bash
DATABASE_URL="ecto://user:pass@host/ex_cortex" \
SECRET_KEY_BASE="$(mix phx.gen.secret)" \
PHX_SERVER=true \
./burrito_out/ex_cortex_linux_x86 start
```

Requires PostgreSQL and Ollama running separately. API keys can be set via environment variables at launch or configured live in the Instinct UI (persisted to DB, takes effect without restart).

### Docker Compose (services)

Docker Compose runs the supporting infrastructure:

```bash
docker compose up -d db ollama             # minimal: just database + LLM
docker compose up -d                       # full: + jaeger, prometheus, grafana, nextcloud
```

---

## Configuration

Most configuration is managed live in the **Instinct** UI at `/instinct`. Settings are persisted to the database and take effect without restart.

### Config Priority

```
Settings DB (Instinct UI) → Application env → Environment variables → Defaults
```

All config reads go through `Settings.resolve/2` — a single function that walks the priority chain.

### Environment Variables

```bash
# Core
PORT=4001                                    # HTTP port
DATABASE_URL=ecto://user:pass@host/db        # PostgreSQL connection
SECRET_KEY_BASE=...                          # Phoenix secret (auto-generated in dev)

# LLM Providers
OLLAMA_URL=http://localhost:11434            # Local Ollama endpoint
OLLAMA_API_KEY=                              # Optional Ollama auth
ANTHROPIC_API_KEY=...                        # Claude API access

# Observability
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

# Integrations (optional)
NEXTCLOUD_URL=http://localhost:8080
NEXTCLOUD_USER=admin
NEXTCLOUD_PASSWORD=admin
```

### LLM Providers

| Provider | Models | Use Case |
|---|---|---|
| **Ollama** (local) | `ministral-3:8b` | Fast, lightweight tasks |
| **Ollama** (local) | `devstral-small-2:24b` | Reliable tool-calling |
| **Claude** (Anthropic) | `claude_haiku`, `claude_sonnet`, `claude_opus` | High-capability tasks |

Fallback chain is configurable — if a model is unavailable, the system tries the next one automatically.

The GitHub tools require a `gh` CLI authenticated on the host and a default repo set in Settings.

---

## Development

### Commands

```bash
mix test                # run the test suite (auto-creates test DB)
mix credo               # static analysis
mix format              # code formatting (Styler rewrites aggressively)
mix excessibility       # LiveView accessibility snapshot tests
mix dialyzer            # type checking
```

### Mix Aliases

```bash
mix setup               # first-time: deps.get, ecto.setup, assets
mix dev                 # start Phoenix server
mix lint                # compile --warnings-as-errors + format check + credo
mix precommit           # lint + test
mix ci                  # full quality gate
mix release.build       # compile + assets + Burrito binary
mix ecto.fresh          # reset DB + seed Dev Team pathway
```

### Quality Notes

- Warnings are errors in test environment
- [Styler](https://github.com/adobe/elixir-styler) aggressively rewrites code formatting — don't fight it
- [Excessibility](https://github.com/coingaming/excessibility) generates HTML snapshots for accessibility testing — these always show as modified in `git status` (not a real problem)
- Credo has ~40 pre-existing refactoring opportunities in the baseline

See [CLAUDE.md](CLAUDE.md) for full contributor conventions.

---

## Tech Stack

### Backend

| Dependency | Purpose |
|---|---|
| [Phoenix](https://phoenixframework.org/) 1.8 | Web framework |
| [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view) 1.1 | Real-time UI |
| [Ecto](https://hexdocs.pm/ecto) + PostgreSQL | Database |
| [Oban](https://hexdocs.pm/oban) | Background job processing |
| [Req](https://hexdocs.pm/req) + [ReqLLM](https://hexdocs.pm/req_llm) | HTTP client + LLM provider abstraction |
| [OpenTelemetry](https://opentelemetry.io/) | Distributed tracing and metrics |
| [Burrito](https://github.com/burrito-elixir/burrito) | Standalone binary releases |
| [Fresh](https://hexdocs.pm/fresh) | WebSocket client |
| [Owl](https://hexdocs.pm/owl) | TUI rendering |

### Frontend

| Dependency | Purpose |
|---|---|
| [Tailwind CSS](https://tailwindcss.com/) v4 | Styling |
| [SaladUI](https://salad-ui.com/) | Component library |
| [Heroicons](https://heroicons.com/) | Icons |
| [MDEx](https://hexdocs.pm/mdex) | Markdown rendering |

### Path Dependencies

| Package | Purpose |
|---|---|
| `ex_cellence` | Core evaluation library — charters, consensus, verdicts |
| `ex_cellence_dashboard` | Read-only visualization components |
| `ex_cellence_ui` | Form and input components |

---

<p align="center">
  <sub>Built with Elixir, Phoenix, and an unreasonable amount of brain metaphors.</sub>
</p>
