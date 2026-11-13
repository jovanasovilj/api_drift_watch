defmodule DriftWatch.Repo do
  use Ecto.Repo,
    otp_app: :drift_watch,
    adapter: Ecto.Adapters.Postgres
end
