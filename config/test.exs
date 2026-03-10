import Config

# Configure ex_cellence to use our repo and test-mode Oban
alias Ecto.Adapters.SQL.Sandbox

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ex_calibur, ExCalibur.Repo,
  username: "andrew",
  hostname: "localhost",
  database: "ex_calibur_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Sandbox,
  pool_size: 5

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ex_calibur, ExCaliburWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "KY64T6XteuWzRYjr2XCLj1kG0olZI3nQ91FCAv0Ky5SVo187Hj3GvvchhKEzFRWY",
  server: false

config :ex_calibur, :sql_sandbox, true

config :ex_cellence, Oban, testing: :manual

config :excessibility,
  endpoint: ExCaliburWeb.Endpoint,
  head_render_path: "/guild-hall",
  browser_mod: Wallaby.Browser,
  live_view_mod: Excessibility.LiveView,
  system_mod: Excessibility.System

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
