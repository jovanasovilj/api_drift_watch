defmodule DriftWatchWeb.DriftyController do
  @moduledoc """
  Serves the drifty demo API and its spec. See `DriftWatch.Drifty`.
  """

  use DriftWatchWeb, :controller

  alias DriftWatch.Drifty

  def spec(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Drifty.spec_json())
  end

  def station(conn, %{"id" => id} = params) do
    {status, body} = Drifty.station(id, pick_drift(params["drift"]))

    conn
    |> put_status(status)
    |> json(body)
  end

  defp pick_drift(drift) do
    if drift in Drifty.drifts(), do: drift, else: Drifty.random_drift()
  end
end
