defmodule DriftWatchWeb.CompareLiveTest do
  use DriftWatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DriftWatch.Drifty

  defp station(drift) do
    {_status, body} = Drifty.station("1", drift)
    Jason.encode!(body)
  end

  test "the example shows five drifts right away", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/compare?example=drifty")

    assert has_element?(view, "#spec-summary", "1 operation")
    assert has_element?(view, "#result h2", "5 drifts")

    for path <- ~w(#/name #/temperature_c #/location/lat #/status #/humidity_pct) do
      assert has_element?(view, "#drifts td", path)
    end
  end

  test "a pasted spec fills the operations and a pasted body is compared", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/compare")
    assert has_element?(view, "#operation[disabled]")

    view |> element("#spec-form") |> render_change(%{"spec" => Drifty.spec_json()})
    assert has_element?(view, ~s(#operation option[value="get /drifty/stations/{id}"]))

    params = %{"operation" => "get /drifty/stations/{id}", "status" => "200", "body" => station("extra_field")}
    view |> element("#response-form") |> render_submit(params)

    assert has_element?(view, "#result h2", "1 drift")
    assert has_element?(view, "#drifts", "#/humidity_pct")

    view |> element("#response-form") |> render_submit(%{params | "body" => station("none")})
    assert has_element?(view, "#no-drift")
  end

  test "explains a spec it cannot read", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/compare")

    view |> element("#spec-form") |> render_change(%{"spec" => ~s({"openapi": "3.0.3"})})

    assert has_element?(view, "#spec-error", "Only 3.1 and 3.2")
    assert has_element?(view, "#operation[disabled]")
  end

  test "explains a body it cannot read", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/compare?example=drifty")

    view
    |> element("#response-form")
    |> render_submit(%{"operation" => "get /drifty/stations/{id}", "status" => "200", "body" => "{oops"})

    assert has_element?(view, "#compare-error", "not valid JSON")
  end
end
