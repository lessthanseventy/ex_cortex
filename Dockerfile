# Build stage
FROM hexpm/elixir:1.18.3-erlang-27.3.4-debian-bookworm-20250428-slim AS build

RUN apt-get update && apt-get install -y build-essential git npm && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

# Copy all sibling packages
COPY ex_cellence/ /app/ex_cellence/
COPY ex_cellence_dashboard/ /app/ex_cellence_dashboard/
COPY ex_cellence_ui/ /app/ex_cellence_ui/

# Copy server package
COPY ex_cellence_server/mix.exs ex_cellence_server/mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

COPY ex_cellence_server/config/ config/
COPY ex_cellence_server/lib/ lib/
COPY ex_cellence_server/priv/ priv/
COPY ex_cellence_server/assets/ assets/

RUN mix assets.deploy
RUN mix release

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y libstdc++6 openssl libncurses5 locales curl \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8

WORKDIR /app

COPY --from=build /app/_build/prod/rel/ex_cellence_server ./

COPY ex_cellence_server/docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 4000

ENTRYPOINT ["/app/entrypoint.sh"]
