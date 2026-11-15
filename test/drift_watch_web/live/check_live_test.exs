defmodule DriftWatchWeb.CheckLiveTest do
  use DriftWatchWeb.ConnCase, async: true
  use Oban.Testing, repo: DriftWatch.Repo

  import DriftWatch.MonitoringFixtures
  import Phoenix.LiveViewTest

  alias DriftWatch.Checker.Drift
  alias DriftWatch.Monitoring
  alias DriftWatch.Workers.CheckWorker

  @extra Drift.new(:extra_field, "#/humidity_pct", "not in spec", "integer")
  @null Drift.new(:unexpected_null, "#/location/lat", "number", "null")

  defp result(drifts), do: {:ok, %{status: 200, duration_ms: 8, body: %{"id" => 1}, drifts: drifts}}

  setup do
    %{check: check_fixture(api_fixture())}
  end

  test "shows the drift history and marks what the latest run still sees", %{conn: conn, check: check} do
    {:ok, _first} = Monitoring.record_run(check, result([@extra]), ~U[2026-11-13 10:00:00Z])
    {:ok, _second} = Monitoring.record_run(check, result([@null]), ~U[2026-11-13 10:01:00Z])
    [null, extra] = Monitoring.list_drifts(check.id)

    {:ok, view, _html} = live(conn, ~p"/checks/#{check.id}")

    assert has_element?(view, "#drift-#{null.id}", "active")
    assert has_element?(view, "#drift-#{extra.id}", "#/humidity_pct")
    refute has_element?(view, "#drift-#{extra.id}", "active")
  end

  test "shows a new run at the top as soon as it is recorded", %{conn: conn, check: check} do
    {:ok, view, _html} = live(conn, ~p"/checks/#{check.id}")
    assert has_element?(view, "#no-runs")
    assert has_element?(view, "#no-drifts")

    {:ok, run} = Monitoring.record_run(check, result([@extra]))

    assert has_element?(view, "#runs-#{run.id}", "Extra field")
    assert has_element?(view, "#drifts", "#/humidity_pct")
  end

  test "ignores runs of other checks", %{conn: conn, check: check} do
    other = check_fixture(api_fixture())
    {:ok, view, _html} = live(conn, ~p"/checks/#{check.id}")

    {:ok, run} = Monitoring.record_run(other, result([@extra]))

    refute has_element?(view, "#runs-#{run.id}")
  end

  test "queues the check from the run now button", %{conn: conn, check: check} do
    {:ok, view, _html} = live(conn, ~p"/checks/#{check.id}")

    view |> element("#run-now") |> render_click()

    assert_enqueued worker: CheckWorker, args: %{check_id: check.id}
  end

  test "goes back to the dashboard for an unknown check", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/checks/0")
  end

  test "says when the check belongs to the drifty demo API", %{conn: conn, check: check} do
    real = check_fixture(api_fixture(%{spec_url: "https://api.example.com/openapi.json"}))

    {:ok, demo_view, _html} = live(conn, ~p"/checks/#{check.id}")
    {:ok, real_view, _html} = live(conn, ~p"/checks/#{real.id}")

    assert has_element?(demo_view, "#demo-note", "at random")
    refute has_element?(real_view, "#demo-note")
  end
end
