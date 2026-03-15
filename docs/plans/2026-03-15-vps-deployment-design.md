# VPS Deployment — Design

**Goal:** One-command deployment of ExCortex to a VPS with HTTPS, auth, and all services bundled. `docker compose up` on a fresh VPS and it just works.

---

## Architecture

```
Internet → Caddy (HTTPS + auth) → ExCortex (port 4001) → Postgres
                                                        → Ollama (optional, can use remote)
```

Caddy handles TLS certificates automatically via Let's Encrypt. Auth options below.

## Files

```
deploy/
  docker-compose.yml      # prod stack
  Caddyfile               # reverse proxy config
  Dockerfile              # builds the Burrito binary in a container
  .env.example            # template for secrets
```

Separate from the dev `docker-compose.yml` in the project root (which stays for anyone who wants Docker dev).

## docker-compose.yml

```yaml
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: ex_cortex
      POSTGRES_PASSWORD: ${DB_PASSWORD:-ex_cortex}
      POSTGRES_DB: ex_cortex
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ex_cortex"]
      interval: 5s
      timeout: 5s
      retries: 5

  app:
    build: ..
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      DATABASE_URL: ecto://ex_cortex:${DB_PASSWORD:-ex_cortex}@db/ex_cortex
      OLLAMA_URL: ${OLLAMA_URL:-http://ollama:11434}
      PORT: "4001"
    ports:
      - "127.0.0.1:4001:4001"  # only expose to localhost, Caddy fronts it

  ollama:
    image: ollama/ollama
    restart: unless-stopped
    volumes:
      - ollama_data:/root/.ollama
    # Optional: comment out if using remote Ollama
    profiles: ["with-ollama"]

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config

volumes:
  pgdata:
  ollama_data:
  caddy_data:
  caddy_config:
```

## Dockerfile

Multi-stage build: compile in an Elixir image, copy the release into a slim runtime image.

```dockerfile
# Build stage
FROM hexpm/elixir:1.19.4-erlang-27.3-debian-bookworm-slim AS build

RUN apt-get update && apt-get install -y build-essential git npm && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

# Copy deps first for layer caching
COPY mix.exs mix.lock ./
COPY config/ config/
RUN mix deps.get --only prod && mix deps.compile

# Copy source
COPY lib/ lib/
COPY priv/ priv/
COPY assets/ assets/

# Build release (standard, not Burrito — no need for standalone binary inside Docker)
RUN mix compile && mix assets.deploy && mix release

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y libstdc++6 openssl libncurses5 locales curl \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8

WORKDIR /app
COPY --from=build /app/_build/prod/rel/ex_cortex ./

# Auto-migrate on startup
CMD ["sh", "-c", "bin/ex_cortex eval 'ExCortex.Release.migrate()' && bin/ex_cortex start"]
```

Note: Inside Docker we use a standard `mix release` (not Burrito) since the container IS the packaging. Burrito is for running outside Docker.

## Auth Options

### Option A: Caddy + HTTP Basic Auth (simplest)

```
cortex.yourdomain.com {
    basicauth {
        andrew $2a$14$... # bcrypt hash
    }
    reverse_proxy app:4001
}
```

Good enough for personal use. Generate hash with `caddy hash-password`.

### Option B: Caddy + Tailscale (zero-config VPN)

Don't expose ports 80/443 at all. Run Tailscale on the VPS, access via `http://vps-name:4001` on your Tailnet. No Caddy needed.

```yaml
# Remove caddy service entirely, change app ports to:
    ports:
      - "4001:4001"  # only accessible via Tailscale
```

### Option C: Nextcloud External Sites + Auth Proxy

If you're already running Nextcloud on the VPS, you can:
1. Use Nextcloud's "External Sites" app to embed ExCortex as an iframe
2. Use Caddy/nginx to check Nextcloud session cookies before proxying to ExCortex
3. Or just use Tailscale (option B) and skip the auth proxy entirely

### Recommendation

**Tailscale** is the least config for personal use. No certificates, no passwords, no auth proxy. Just `tailscale up` on the VPS and your devices, and ExCortex is accessible on your private network.

If you need public access (sharing with others), **Caddy + basic auth** is the next simplest.

## .env.example

```env
# Required
# DB_PASSWORD=change-me

# Optional — defaults work for Docker stack
# OLLAMA_URL=http://ollama:11434
# PORT=4001

# For remote Ollama (skip local ollama container)
# OLLAMA_URL=https://api.ollama.com
# OLLAMA_API_KEY=your-key

# For Claude
# ANTHROPIC_API_KEY=sk-ant-...
```

## Deployment Flow

```bash
# On your VPS
git clone <repo> && cd ex_cortex/deploy
cp .env.example .env
# Edit .env if needed (or don't — defaults work)

# With local Ollama:
docker compose --profile with-ollama up -d

# Without Ollama (using remote):
docker compose up -d

# That's it. Access at https://cortex.yourdomain.com (or via Tailscale)
```

## What About Ollama?

Three options for LLM access on a VPS:

1. **Local Ollama in Docker** — works but VPS needs enough RAM (8GB+ for small models). Use `--profile with-ollama`.
2. **Remote Ollama** — point `OLLAMA_URL` at your home machine or a GPU server running Ollama. Requires the remote machine to be accessible.
3. **Claude only** — set `ANTHROPIC_API_KEY` in Instinct, don't run Ollama at all. Fastest to set up, costs per API call.

For a personal VPS, option 3 (Claude only) or option 2 (remote Ollama on a home server) makes the most sense unless the VPS has a GPU.
