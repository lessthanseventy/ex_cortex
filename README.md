# Excellence Server

Phoenix web UI for the [Excellence](../ex_cellence) multi-agent consensus framework. Install a guild, recruit members, wire up knowledge sources, and evaluate content through collaborative AI review.

## Architecture

- **Guild Hall** — install one guild at a time (Content Moderation, Code Review, Accessibility Review, etc.)
- **Town Square** — recruit individual members across 4 categories (Editors, Analysts, Specialists, Advisors) at 3 rank tiers
- **Library** — browse Books (configurable sources) and Scrolls (pre-configured feeds)
- **Stacks** — manage active source connections
- **Evaluate** — submit content for guild review
- **Lodge** — dashboard with metrics and decision history

## Prerequisites

- [Podman](https://podman.io/) or Docker with Compose

## Development

One command:

```sh
docker compose up --build
```

This starts:

| Service | Description | Port |
|---------|-------------|------|
| **app** | Phoenix dev server with live reload | `localhost:4001` |
| **db** | TimescaleDB (PostgreSQL 16) | `localhost:5433` |
| **ollama** | Ollama with gemma3:4b and phi4-mini | internal |

Your source code is bind-mounted into the container. File changes trigger live reload automatically — no rebuild needed for code, template, or CSS changes.

### Running tests

```sh
docker compose exec app mix test
```

Or locally if you have Elixir installed:

```sh
mix test
```

### Local dev (without Docker)

If you prefer running the app outside Docker, start just the dependencies:

```sh
docker compose up db ollama
```

Then configure `config/dev.exs` to point at `localhost:5433` for the database and `localhost:11434` for Ollama, and run:

```sh
mix deps.get
mix ecto.setup
mix phx.server
```

## Production

The production build uses `Dockerfile` — a two-stage Mix release build on minimal Debian slim:

```sh
docker build -t excellence-server -f Dockerfile ..
```

Required environment variables:

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | Ecto connection string |
| `SECRET_KEY_BASE` | Generate with `mix phx.gen.secret` |
| `PHX_HOST` | Public hostname |
| `OLLAMA_URL` | Ollama API endpoint |

## Sandbox Execution

Books in the Library can have an optional sandbox configuration. When a source worker detects a change, it runs the specified tool and feeds both the source content and tool output to guild members for evaluation.

Two modes:

- **Host mode** — runs tools using the local environment (mise/asdf). Default when no image is specified.
- **Container mode** — runs tools in a Podman container for full isolation.

```elixir
# Host mode
sandbox: %{cmd: "mix excessibility", timeout: 120_000}

# Container mode
sandbox: %{mode: :container, image: "elixir:1.17", cmd: "mix credo", timeout: 120_000}
```

## Project Structure

```
lib/
  ex_cellence_server/
    evaluator.ex          # Orchestrates guild evaluation via Excellence
    sandbox.ex            # Host/container tool execution
    members/member.ex     # Member catalogue (18 roles, 4 categories, 3 ranks)
    sources/
      book.ex             # Book & Scroll catalogue
      source.ex           # Ecto schema for active sources
      source_worker.ex    # GenServer that fetches + evaluates
  ex_cellence_server_web/
    live/                 # LiveView pages
    components/           # Shared components and layouts
docker-compose.yml        # Dev stack (db + ollama + app with live reload)
Dockerfile                # Production release build
Dockerfile.dev            # Dev build with inotify + live reload
```
