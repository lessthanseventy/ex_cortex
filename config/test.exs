import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ex_cellence_server, ExCellenceServer.Repo,
  username: "andrew",
  hostname: "localhost",
  database: "ex_cellence_server_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ex_cellence_server, ExCellenceServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "KY64T6XteuWzRYjr2XCLj1kG0olZI3nQ91FCAv0Ky5SVo187Hj3GvvchhKEzFRWY",
  server: false

# Configure ex_cellence to use our repo and test-mode Oban
config :ex_cellence, Excellence.Repo,
  username: "andrew",
  hostname: "localhost",
  database: "ex_cellence_server_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :ex_cellence, Oban, testing: :manual

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
