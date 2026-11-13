defmodule DriftWatch.DriftyTest do
  use ExUnit.Case, async: true

  alias DriftWatch.Checker
  alias DriftWatch.Drifty
  alias DriftWatch.Specs

  # The checker run against the drifty API must find exactly the drift that was asked for.
  # This tests both sides: the demo API breaks its spec the way it claims and the checker
  # catches it.

  @expected %{
    "none" => [],
    "missing_field" => [{:missing_field, "#/name"}],
    "wrong_type" => [{:wrong_type, "#/temperature_c"}],
    "unexpected_null" => [{:unexpected_null, "#/location/lat"}],
    "extra_field" => [{:extra_field, "#/humidity_pct"}],
    "invalid_value" => [{:invalid_value, "#/status"}],
    "undocumented_status" => [{:undocumented_status, "#"}]
  }

  setup do
    {:ok, spec} = Specs.parse(Drifty.spec_json())
    {:ok, operation} = Specs.operation(spec, "get", "/drifty/stations/{id}")
    %{spec: spec, operation: operation}
  end

  defp drifts(context, id, drift) do
    {status, body} = Drifty.station(id, drift)
    {:ok, drifts} = Checker.compare(context.spec, context.operation, status, body)
    Enum.map(drifts, &{&1.kind, &1.path})
  end

  test "every drift name has an expectation" do
    assert Enum.sort(Drifty.drifts()) == Enum.sort(Map.keys(@expected))
  end

  for {drift, expected} <- @expected do
    test "#{drift} gives exactly the expected drift for every station", context do
      for id <- ["1", "2"] do
        assert drifts(context, id, unquote(drift)) == unquote(Macro.escape(expected))
      end
    end
  end

  test "an unknown station answers with the documented 404", context do
    assert Drifty.station("99", "none") == {404, %{"message" => "Station not found"}}
    assert drifts(context, "99", "none") == []
    assert drifts(context, "abc", "none") == []
  end

  test "random_drift only returns known drifts" do
    for _ <- 1..50, do: assert(Drifty.random_drift() in Drifty.drifts())
  end
end
