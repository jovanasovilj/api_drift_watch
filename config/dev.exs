import Config

config :drift_watch, DriftWatch.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "drift_watch_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :drift_watch, DriftWatchWeb.Endpoint,
  # Only this machine can reach the dev server.
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "GGrH5rUXIWtIiVBzIA7iCsUJNU7IJSfCDcLqUaSAyHB9CVHehvQYmFRjSHIkCBiV",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:drift_watch, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:drift_watch, ~w(--watch)]}
  ]

config :drift_watch, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :plug_init_mode, :runtime
config :phoenix, :stacktrace_depth, 20

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
