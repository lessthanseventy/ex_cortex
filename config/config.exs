# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  ex_cortex: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure the endpoint
config :ex_cortex, ExCortexWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ExCortexWeb.ErrorHTML, json: ExCortexWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ExCortex.PubSub,
  live_view: [signing_salt: "dE89EITe"]

config :ex_cortex, Oban,
  engine: Oban.Engines.Basic,
  queues: [default: 10],
  repo: ExCortex.Repo

config :ex_cortex, :model_fallback_chain, ["devstral-small-2:24b"]

config :ex_cortex, :nextcloud_roles, %{
  "admin" => :super_admin,
  "andrew" => :super_admin,
  "robyn" => :admin,
  "jude" => :user
}

config :ex_cortex,
  ecto_repos: [ExCortex.Repo],
  generators: [timestamp_type: :utc_datetime]

config :ex_cortex,
  nextcloud_url: System.get_env("NEXTCLOUD_URL", "http://localhost:8080"),
  nextcloud_user: System.get_env("NEXTCLOUD_USER", "admin"),
  nextcloud_password: System.get_env("NEXTCLOUD_PASSWORD", "admin")

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# OpenTelemetry
config :opentelemetry,
  resource: [service: [name: "ex_cortex", version: "0.1.0"]],
  span_processor: :batch,
  traces_exporter: :otlp

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  ex_cortex: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),

    # Import environment specific config. This must remain at the bottom
    # of this file so it overrides the configuration defined above.
    cd: Path.expand("..", __DIR__)
  ]

import_config "#{config_env()}.exs"
