import Config

# runtime.exs runs at boot for all environments (including releases).
# For ExCortex, the goal is zero-config: just run the binary.

# Always start the web server in releases
if System.get_env("PHX_SERVER") || config_env() == :prod do
  config :ex_cortex, ExCortexWeb.Endpoint, server: true
end

port = String.to_integer(System.get_env("PORT") || "4001")
config :ex_cortex, ExCortexWeb.Endpoint, http: [port: port, ip: {0, 0, 0, 0}]

# LLM providers — env vars are the initial source, Instinct UI overrides at runtime
config :ex_cortex,
  ollama_url: System.get_env("OLLAMA_URL") || "http://127.0.0.1:11434",
  ollama_api_key: System.get_env("OLLAMA_API_KEY"),
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")

# Database — use DATABASE_URL if set, otherwise fall back to dev defaults
# Skip in test so DATABASE_URL doesn't override the test database config
if config_env() != :test do
  if database_url = System.get_env("DATABASE_URL") do
    config :ex_cortex, ExCortex.Repo, url: database_url
  end
end

if config_env() == :prod do
  # Database — use DATABASE_URL if set, otherwise default to local postgres
  pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")

  if database_url = System.get_env("DATABASE_URL") do
    config :ex_cortex, ExCortex.Repo,
      url: database_url,
      pool_size: pool_size
  else
    config :ex_cortex, ExCortex.Repo,
      username: System.get_env("USER") || "postgres",
      hostname: "localhost",
      database: "ex_cortex",
      pool_size: pool_size
  end

  # Secret key — auto-generate and persist to ~/.config/ex_cortex/secret
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      (fn ->
         secret_path = Path.join([System.get_env("HOME") || "/tmp", ".config", "ex_cortex", "secret"])

         case File.read(secret_path) do
           {:ok, secret} ->
             String.trim(secret)

           _ ->
             secret = 64 |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, 64)
             secret_path |> Path.dirname() |> File.mkdir_p!()
             File.write!(secret_path, secret)
             secret
         end
       end).()

  host = System.get_env("PHX_HOST") || "localhost"

  config :ex_cortex, ExCortexWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
    secret_key_base: secret_key_base
end
