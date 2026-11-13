import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :drift_watch, DriftWatch.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "drift_watch_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :drift_watch, DriftWatchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "V7Y6IEpJVVJOqeUSTjF22HxpKwQW0p9GbPcQsu0XRcF26ZnCjpuXzDu4hTAl986b",
  server: false

# Jobs only run when a test asks for it
config :drift_watch, Oban, testing: :manual

# Route every outgoing request to Req.Test stubs
config :drift_watch, req_options: [plug: {Req.Test, DriftWatch.HTTP}]

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
