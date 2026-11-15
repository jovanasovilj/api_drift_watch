import Config

config :drift_watch, DriftWatchWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DriftWatchWeb.ErrorHTML, json: DriftWatchWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: DriftWatch.PubSub,
  live_view: [signing_salt: "F2SFL4rm"]

# The scheduler runs every minute and queues the checks that are due
config :drift_watch, Oban,
  engine: Oban.Engines.Basic,
  repo: DriftWatch.Repo,
  queues: [default: 1, checks: 5],
  plugins: [
    {Oban.Plugins.Cron, crontab: [{"* * * * *", DriftWatch.Workers.SchedulerWorker}]},
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60}
  ]

config :drift_watch,
  ecto_repos: [DriftWatch.Repo],
  generators: [timestamp_type: :utc_datetime]

config :esbuild,
  version: "0.25.4",
  drift_watch: [
    args:
      ~w(js/app.js js/theme.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :phoenix_live_view,
  root_tag_attribute: "phx-r"

config :tailwind,
  version: "4.3.3",
  drift_watch: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Stays at the bottom so the environment config overrides everything above.
import_config "#{config_env()}.exs"
