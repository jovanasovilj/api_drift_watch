defmodule DriftWatchWeb.DriftyControllerTest do
  use DriftWatchWeb.ConnCase, async: true

  alias DriftWatch.Checker
  alias DriftWatch.Drifty
  alias DriftWatch.Specs

  test "serves its OpenAPI spec", %{conn: conn} do
    conn = get(conn, ~p"/drifty/openapi.json")

    assert json_response(conn, 200)["openapi"] == "3.1.0"
  end

  test "serves a station with the drift that was asked for", %{conn: conn} do
    assert %{"humidity_pct" => 81} = conn |> get(~p"/drifty/stations/1?drift=extra_field") |> json_response(200)
    assert %{"message" => _} = conn |> get(~p"/drifty/stations/1?drift=undocumented_status") |> json_response(500)
    assert %{"message" => _} = conn |> get(~p"/drifty/stations/99?drift=none") |> json_response(404)
  end

  test "picks a random drift for an unknown drift name", %{conn: conn} do
    conn = get(conn, ~p"/drifty/stations/1?drift=chaos")

    assert conn.status in [200, 500]
  end

  # The checker goes through the whole HTTP stack here, with the endpoint as its plug.
  test "the checker finds the drift through HTTP" do
    {:ok, spec} = Specs.parse(Drifty.spec_json())
    api = %{base_url: "http://drifty.test", spec: spec}
    check = %{method: "get", path: "/drifty/stations/{id}", params: %{"id" => 2, "drift" => "wrong_type"}}

    assert {:ok, result} = Checker.run(api, check, plug: DriftWatchWeb.Endpoint)
    assert result.status == 200
    assert [%{kind: :wrong_type, path: "#/temperature_c", expected: "number", actual: "string"}] = result.drifts
  end
end
