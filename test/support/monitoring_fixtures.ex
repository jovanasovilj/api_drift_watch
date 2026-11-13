defmodule DriftWatch.MonitoringFixtures do
  @moduledoc """
  Builds APIs and checks for tests. They point at the drifty demo API on a fake host.
  """

  alias DriftWatch.Monitoring

  @doc """
  Creates an API.
  """
  def api_fixture(attrs \\ %{}) do
    {:ok, api} =
      attrs
      |> Enum.into(%{
        name: "Drifty #{System.unique_integer([:positive])}",
        base_url: "http://drifty.test",
        spec_url: "http://drifty.test/drifty/openapi.json"
      })
      |> Monitoring.create_api()

    api
  end

  @doc """
  Creates a check for station 1 on `api`.
  """
  def check_fixture(api, attrs \\ %{}) do
    {:ok, check} =
      attrs
      |> Enum.into(%{api_id: api.id, method: "get", path: "/drifty/stations/{id}", params: %{"id" => 1}})
      |> Monitoring.create_check()

    Monitoring.get_check!(check.id)
  end
end
