defmodule DriftWatchWeb.DashboardLiveTest do
  use DriftWatchWeb.ConnCase, async: true
  use Oban.Testing, repo: DriftWatch.Repo

  import DriftWatch.MonitoringFixtures
  import Phoenix.LiveViewTest

  alias DriftWatch.Checker.Drift
  alias DriftWatch.Monitoring
  alias DriftWatch.Workers.CheckWorker

  defp result(drifts), do: {:ok, %{status: 200, duration_ms: 8, body: %{}, drifts: drifts}}

  test "explains how to add an API when there is none", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#empty-state")
  end

  test "shows every check with the drift of its latest run", %{conn: conn} do
    api = api_fixture(%{name: "Weather"})
    check = check_fixture(api)
    idle = check_fixture(api, %{params: %{"id" => 2}})
    {:ok, _run} = Monitoring.record_run(check, result([Drift.new(:missing_field, "#/name", "required", "missing")]))

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#api-#{api.id} h2", "Weather")
    assert has_element?(view, "#check-#{check.id}", "Missing field")
    assert has_element?(view, "#check-#{check.id}", "200")
    assert has_element?(view, "#check-#{idle.id}", "Not run yet")
  end

  test "updates live when a run is recorded", %{conn: conn} do
    check = check_fixture(api_fixture())
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#check-#{check.id}", "Wrong type")

    {:ok, _run} = Monitoring.record_run(check, result([Drift.new(:wrong_type, "#/id", "integer", "string")]))

    assert has_element?(view, "#check-#{check.id}", "Wrong type")
  end

  test "queues a check from the run now button", %{conn: conn} do
    check = check_fixture(api_fixture())
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#run-now-#{check.id}") |> render_click()

    assert_enqueued worker: CheckWorker, args: %{check_id: check.id}
  end
end
