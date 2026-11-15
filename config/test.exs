import Config

config :drift_watch, DriftWatch.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "drift_watch_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Async tests compare many pasted specs at once.
config :drift_watch, DriftWatch.Sandbox, max_running: 64

config :drift_watch, DriftWatchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "V7Y6IEpJVVJOqeUSTjF22HxpKwQW0p9GbPcQsu0XRcF26ZnCjpuXzDu4hTAl986b",
  server: false

# Jobs only run when a test asks for it.
config :drift_watch, Oban, testing: :manual

# Route every outgoing request to Req.Test stubs.
config :drift_watch, req_options: [plug: {Req.Test, DriftWatch.HTTP}]

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix,
  sort_verified_routes_query_params: true

config :phoenix_live_view,
  enable_expensive_runtime_checks: true
