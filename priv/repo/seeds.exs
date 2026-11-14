# Adds the drifty demo API that runs inside this app and four real public APIs, each with a
# check. Run it with `mix run priv/repo/seeds.exs`. APIs that already exist are skipped.
#
# Intervals stay polite: GitHub allows 60 calls an hour without a token and PokeAPI asks
# clients to cache, so those run every 15 and 30 minutes.

alias DriftWatch.Monitoring
alias DriftWatch.Monitoring.Api
alias DriftWatch.Repo

drifty_url = DriftWatchWeb.Endpoint.url()

apis = [
  %{
    name: "Drifty Weather Stations",
    base_url: drifty_url,
    spec_url: drifty_url <> "/drifty/openapi.json",
    checks: [
      %{path: "/drifty/stations/{id}", params: %{"id" => 1}, interval_minutes: 1},
      %{path: "/drifty/stations/{id}", params: %{"id" => 2}, interval_minutes: 2},
      %{path: "/drifty/stations/{id}", params: %{"id" => 99}, interval_minutes: 5}
    ]
  },
  %{
    name: "Open-Meteo Forecast",
    base_url: "https://api.open-meteo.com",
    spec_url: "https://raw.githubusercontent.com/open-meteo/open-meteo/main/openapi/forecast.yml",
    checks: [
      %{
        path: "/v1/forecast",
        params: %{
          "latitude" => 52.1,
          "longitude" => 5.18,
          "current" => "temperature_2m,wind_speed_10m",
          "hourly" => "temperature_2m",
          "forecast_days" => 1
        },
        interval_minutes: 15
      }
    ]
  },
  %{
    name: "PokeAPI",
    base_url: "https://pokeapi.co",
    spec_url: "https://raw.githubusercontent.com/PokeAPI/pokeapi/master/openapi.yml",
    checks: [%{path: "/api/v2/pokemon/{id}/", params: %{"id" => "pikachu"}, interval_minutes: 30}]
  },
  %{
    name: "GitHub REST API",
    base_url: "https://api.github.com",
    spec_url:
      "https://raw.githubusercontent.com/github/rest-api-description/main/descriptions-next/api.github.com/api.github.com.json",
    checks: [
      %{
        path: "/repos/{owner}/{repo}",
        params: %{"owner" => "phoenixframework", "repo" => "phoenix"},
        interval_minutes: 15
      }
    ]
  },
  %{
    name: "Swagger Petstore 3.1",
    base_url: "https://petstore31.swagger.io/api/v31",
    spec_url: "https://petstore31.swagger.io/api/v31/openapi.json",
    checks: [%{path: "/pet/{petId}", params: %{"petId" => 1}, interval_minutes: 10}]
  }
]

for %{name: name, checks: checks} = attrs <- apis do
  if Repo.get_by(Api, name: name) do
    IO.puts("#{name} already exists")
  else
    {:ok, api} = Monitoring.create_api(attrs)

    for check <- checks do
      {:ok, _check} = Monitoring.create_check(Map.merge(check, %{api_id: api.id, method: "get"}))
    end

    IO.puts("#{name} is watched at #{api.base_url}")
  end
end
