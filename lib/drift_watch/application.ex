defmodule DriftWatch.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
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
      # Start to serve requests, typically the last entry
      DriftWatchWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DriftWatch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DriftWatchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
