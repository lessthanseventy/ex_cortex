# ExCalibur

ExCalibur is a local-first AI agent platform. You give it teams of AI agents, wire them up to your data sources, and they work autonomously — reviewing code, triaging issues, summarizing feeds, running tests, filing bugs, and improving the system itself.

It runs entirely on your machine. No cloud, no SaaS, no data leaving your network. Just Ollama, a Postgres database, and a Phoenix web UI.

---

## What it can do

### Review your pull requests

Point the Code Review guild at your repo. Every new commit triggers a multi-agent review: a Security Auditor checks for vulnerabilities, a Style Reviewer flags readability issues, an Architecture Reviewer looks at structural concerns. Each agent runs independently, then they vote on a verdict. You get a structured report with confidence scores and reasoning.

Works on any language. Takes about 30 seconds per PR with local models.

### Watch your feeds and stay on top of things

Subscribe to RSS feeds, newsletters, Nextcloud files, or webhooks. When new content arrives, the appropriate guild evaluates it automatically. The Risk Assessment guild can flag concerning content in your security feeds. The Content Moderation guild can screen community submissions. The Incident Triage guild can prioritize your on-call alerts.

Everything lands in the Lodge — a live dashboard showing verdict history, agent confidence trends, and drift over time.

### Monitor your own codebase

The built-in **Analyst Sweep** runs every 4 hours. It:
- Reads your codebase
- Runs `mix credo` (or your linter)
- Finds test coverage gaps, unhandled errors, TODO comments, and complexity hotspots
- Cross-references what's already in your GitHub backlog
- Files new issues for anything worth fixing

You end up with a continuously-maintained backlog driven by actual analysis, not just manual triage.

### Improve itself

This is the interesting one. ExCalibur includes a Dev Team guild that reads its own GitHub issues, writes fixes, reviews the code, runs the test suite, and merges approved changes. The loop:

```
Issue filed → PM Triage → Code Writer → Code Reviewer → QA → Merge/Escalate
```

Low-risk changes (formatting, tests, small fixes) get auto-merged. Anything touching core logic creates a proposal in the Lodge for you to approve. The system literally gets better on its own, and you stay in control of what lands.

### Run structured multi-step workflows

Quests are pipelines where each step is a team of agents with access to tools. A step can:

- Read files, search GitHub, query your lore store
- Run sandboxed shell commands (`mix test`, `mix credo`, etc.)
- Write files, create commits, open pull requests
- File issues, send emails, post to Nextcloud Talk

Each tool call that touches the outside world goes through a Proposal — an approval record you can review, approve, or reject from the Lodge. Agents that call safe tools (read, search, fetch) proceed immediately. Agents that want to write or send things create a proposal and wait.

### Build your own guild

Charters are just Elixir modules with metadata functions. Define your own roles with custom system prompts, pick models and perspectives for each role, wire up consensus strategy, and install it. The existing guilds are all written this way — there's nothing special about them.

---

## How it works

```mermaid
flowchart TD
    Sources["Sources
    git · rss · webhook
    github · obsidian · email"]

    Sources --> Input

    subgraph Eval [Guild Evaluation]
        Input --> RoleA["Member A<br/>alpha perspective"]
        Input --> RoleB["Member B<br/>beta perspective"]
        Input --> RoleC["Member C<br/>strict perspective"]
        RoleA & RoleB & RoleC --> Consensus["Consensus<br/>vote → verdict"]
    end

    Eval --> Lodge["Lodge<br/>dashboard + proposals"]
    Lodge --> Lore["Lore store<br/>knowledge across runs"]
    Lore --> Eval
```

Agents in a step have access to tools. Safe tools execute immediately. Write and dangerous tools create Proposals.

```mermaid
flowchart TD
    Agent[Agent] --> ToolCall{Tool call}
    ToolCall -- read / search / fetch --> Exec[Execute now]
    ToolCall -- write / create / send --> Proposal[Create Proposal]
    Exec --> Result[Result back to agent]
    Proposal --> Lodge2[Lodge: awaiting approval]
    Lodge2 -- approved --> Exec
```

---

## Built-in guilds

| Guild | What it does |
|---|---|
| **Code Review** | Security, style, and architecture review |
| **Content Moderation** | Safety, bias, and policy checking |
| **Accessibility Review** | WCAG compliance and assistive tech compatibility |
| **Risk Assessment** | Risk identification, compliance, fraud signals |
| **Performance Audit** | Bottleneck and scalability analysis |
| **Dependency Audit** | Vulnerability and version scanning |
| **Incident Triage** | Severity classification and response suggestions |
| **Contract Review** | Legal document analysis and risk flagging |
| **Dev Team** | Self-improvement — code, reviews, tests, merges |

Each guild can be installed from the Guild Hall. Installing a guild creates member records in the database and wires them to the evaluation pipeline.

---

## Built-in sources

| Type | What it watches |
|---|---|
| `git` | Commits in a local git repo |
| `directory` | File changes in a directory |
| `feed` | RSS/Atom feeds |
| `webhook` | `POST /api/webhooks/:id` endpoint |
| `url` | Content changes at a URL |
| `websocket` | WebSocket stream |
| `github_issues` | GitHub issues matching a label |
| `obsidian` | New or changed notes in an Obsidian vault |
| `nextcloud` | Nextcloud activity feed |
| `email` | Email inbox |
| `media` | Video/audio files for transcription and analysis |

Install a source from the Library (using a Book template) or define one manually in Stacks.

---

## Running it

```bash
docker compose up
```

That's it. Starts the app, Postgres, Ollama, Jaeger, Prometheus, and Grafana. Visit http://localhost:4001.

| Service | URL |
|---|---|
| ExCalibur | http://localhost:4001 |
| Jaeger traces | http://localhost:16686 |
| Grafana | http://localhost:3000 |
| Nextcloud (optional) | http://localhost:8080 |

Custom port: `PORT=4002 docker compose up`

### First run

```bash
# Reset DB and install the Dev Team guild
mix ecto.fresh
```

Then open the Guild Hall and install whichever guild fits your use case.

### Local dev without Docker

```bash
docker compose up db ollama jaeger   # just the deps
mix setup
mix phx.server
```

---

## Tools available to agents

Agents call tools during quest steps. Steps declare which tools they're allowed to use.

**Safe** (execute immediately): `read_file`, `list_files`, `fetch_url`, `web_search`, `query_lore`, `search_github`, `read_github_issue`, `search_obsidian`, `read_obsidian`, `search_email`, `read_email`, `read_pdf`, `convert_document`, `describe_image`, `read_image_text`, `transcribe_audio`, `analyze_video`, `jq_query`, `run_sandbox` (allowlisted mix commands only), `query_jaeger`, `search_nextcloud`, `read_nextcloud`, `read_nextcloud_notes`, `query_dictionary`

**Write** (create Proposal): `write_file`, `edit_file`, `git_commit`, `git_push`, `open_pr`, `create_obsidian_note`, `setup_worktree`, `write_nextcloud`, `create_nextcloud_note`, `nextcloud_calendar`

**Dangerous** (create Proposal): `create_github_issue`, `comment_github`, `merge_pr`, `close_issue`, `git_pull`, `send_email`, `run_quest`, `restart_app`, `nextcloud_talk`

---

## Configuration

Most things are configurable at `/settings` in the UI. The main env vars:

```bash
OLLAMA_URL=http://localhost:11434       # local Ollama endpoint
OLLAMA_API_KEY=                         # optional
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

# Nextcloud (optional)
NEXTCLOUD_URL=http://localhost:8080
NEXTCLOUD_USER=admin
NEXTCLOUD_PASSWORD=admin

# Production
SECRET_KEY_BASE=...
PHX_HOST=your-host.com
DATABASE_URL=ecto://user:pass@host/db
```

The GitHub tools need a `gh` CLI authenticated on the host and a default repo set in Settings.

---

## Observability

All requests, DB queries, and LLM calls emit OpenTelemetry traces. They land in Jaeger automatically when running via Docker Compose. Agents can query their own traces using the `query_jaeger` tool — useful for the self-improvement loop to verify that a change actually made things faster.

---

## Development

```bash
mix test                 # run the test suite
mix credo                # static analysis
mix format               # format (Styler rewrites aggressively — don't fight it)
mix excessibility        # LiveView accessibility snapshot tests
mix precommit            # compile + format + test
```

See [CLAUDE.md](CLAUDE.md) for contributor conventions.
