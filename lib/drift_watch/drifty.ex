defmodule DriftWatch.Drifty do
  @moduledoc """
  A small weather station API that breaks its own spec on purpose.

  It runs inside this app so a demo always has drift to show, without depending on a public
  API that happens to behave that day. Each response either follows the spec or breaks it in
  exactly one way. The spec lives in `priv/drifty/openapi.json`.
  """

  @spec_path Path.expand("../../priv/drifty/openapi.json", __DIR__)
  @external_resource @spec_path
  @spec_json File.read!(@spec_path)

  @drifts [
    "none",
    "missing_field",
    "wrong_type",
    "unexpected_null",
    "extra_field",
    "invalid_value",
    "undocumented_status"
  ]

  @stations %{
    1 => %{
      "id" => 1,
      "name" => "Utrecht De Bilt",
      "status" => "online",
      "location" => %{"lat" => 52.1, "lon" => 5.18},
      "temperature_c" => 12.4,
      "tags" => ["urban", "reference"],
      "operator" => "Utrecht Weather Club"
    },
    2 => %{
      "id" => 2,
      "name" => "Texel Lighthouse",
      "status" => "offline",
      "location" => %{"lat" => 53.18, "lon" => 4.85},
      "temperature_c" => 9.0,
      "tags" => ["coastal"],
      "operator" => nil
    }
  }

  @doc """
  Returns the OpenAPI spec as JSON text.
  """
  def spec_json, do: @spec_json

  @doc """
  Tells whether a watched API is this demo, by the path its spec is served at.
  """
  def demo?(%{spec_url: spec_url}), do: URI.parse(spec_url).path == "/drifty/openapi.json"

  @doc """
  Lists the drifts the API can be asked for, `"none"` included.
  """
  def drifts, do: @drifts

  @doc """
  Picks a drift at random. Half of the responses follow the spec.
  """
  def random_drift do
    if :rand.uniform() < 0.5, do: "none", else: @drifts |> tl() |> Enum.random()
  end

  @doc """
  Returns `{status, body}` for a station id and a drift name.
  """
  def station(id, drift) when drift in @drifts do
    with {number, ""} <- Integer.parse(id),
         {:ok, station} <- Map.fetch(@stations, number) do
      station
      |> Map.put("updated_at", :second |> DateTime.utc_now() |> DateTime.to_iso8601())
      |> apply_drift(drift)
    else
      _not_found -> {404, %{"message" => "Station not found"}}
    end
  end

  defp apply_drift(station, "none"), do: {200, station}
  defp apply_drift(station, "missing_field"), do: {200, Map.delete(station, "name")}
  defp apply_drift(station, "wrong_type"), do: {200, Map.update!(station, "temperature_c", &to_string/1)}
  defp apply_drift(station, "unexpected_null"), do: {200, put_in(station, ["location", "lat"], nil)}
  defp apply_drift(station, "extra_field"), do: {200, Map.put(station, "humidity_pct", 81)}
  defp apply_drift(station, "invalid_value"), do: {200, Map.put(station, "status", "maintenance")}
  defp apply_drift(_station, "undocumented_status"), do: {500, %{"message" => "Sensor gateway timed out"}}
end
