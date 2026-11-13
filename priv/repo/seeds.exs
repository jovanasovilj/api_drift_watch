# Adds the drifty demo API that runs inside this app, with a few checks.
# Run it with `mix run priv/repo/seeds.exs`. Running it again changes nothing.

alias DriftWatch.Monitoring
alias DriftWatch.Monitoring.Api
alias DriftWatch.Repo

base_url = DriftWatchWeb.Endpoint.url()
name = "Drifty Weather Stations"

api =
  with nil <- Repo.get_by(Api, name: name) do
    {:ok, api} = Monitoring.create_api(%{name: name, base_url: base_url, spec_url: base_url <> "/drifty/openapi.json"})

    checks = [
      %{params: %{"id" => 1}, interval_minutes: 1},
      %{params: %{"id" => 2}, interval_minutes: 2},
      %{params: %{"id" => 99}, interval_minutes: 5}
    ]

    for attrs <- checks do
      {:ok, _check} =
        Monitoring.create_check(Map.merge(attrs, %{api_id: api.id, method: "get", path: "/drifty/stations/{id}"}))
    end

    api
  end

IO.puts("#{api.name} is watched at #{api.base_url}")
