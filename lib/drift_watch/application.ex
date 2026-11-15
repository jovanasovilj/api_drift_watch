defmodule DriftWatch.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DriftWatchWeb.Telemetry,
      DriftWatch.Repo,
      {DNSCluster, query: Application.get_env(:drift_watch, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DriftWatch.PubSub},
      {Oban, Application.fetch_env!(:drift_watch, Oban)},
      DriftWatch.Sandbox,
      DriftWatchWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: DriftWatch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DriftWatchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
