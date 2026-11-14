defmodule DriftWatch.ComparisonTest do
  use ExUnit.Case, async: true

  alias DriftWatch.Checker.Drift
  alias DriftWatch.Comparison
  alias DriftWatch.Drifty

  @operation "get /drifty/stations/{id}"

  defp spec do
    {:ok, %{spec: spec}} = Comparison.load_spec(Drifty.spec_json())
    spec
  end

  defp station(drift) do
    {_status, body} = Drifty.station("1", drift)
    Jason.encode!(body)
  end

  # Nine levels of ten aliases each. Under 1 KB of text that expands to a billion strings.
  defp alias_bomb do
    levels = ~w(a b c d e f g h i)

    body =
      levels
      |> Enum.with_index()
      |> Enum.map_join(fn
        {name, 0} -> "#{name}: &#{name}\n" <> String.duplicate("  - text\n", 10)
        {name, i} -> "#{name}: &#{name}\n" <> String.duplicate("  - *#{Enum.at(levels, i - 1)}\n", 10)
      end)

    "openapi: 3.1.0\n" <> body
  end

  describe "load_spec/1" do
    test "parses a spec and lists its operations" do
      assert {:ok, %{spec: %{"openapi" => "3.1.0"}, operations: [{"get", "/drifty/stations/{id}"}]}} =
               Comparison.load_spec(Drifty.spec_json())
    end

    test "rejects text that is not a supported spec" do
      assert Comparison.load_spec("{") == {:error, :not_json_or_yaml}
      assert Comparison.load_spec(~s({"openapi": "3.0.3"})) == {:error, {:unsupported_version, "3.0.3"}}
      assert Comparison.load_spec("title: no spec") == {:error, :not_an_openapi_spec}
    end

    test "rejects a spec over 1 MB before parsing it" do
      assert Comparison.load_spec(String.duplicate(" ", 1_000_001)) == {:error, :too_large}
    end

    test "stops a YAML alias bomb" do
      assert byte_size(alias_bomb()) < 1_000
      assert Comparison.load_spec(alias_bomb()) == {:error, :too_much_memory}
    end
  end

  describe "compare/2" do
    test "finds the drifts in a pasted body" do
      params = %{"operation" => @operation, "status" => "200", "body" => station("wrong_type")}

      assert {:ok, [%Drift{kind: :wrong_type, path: "#/temperature_c"}]} = Comparison.compare(spec(), params)
    end

    test "finds nothing in a body that follows the spec" do
      params = %{"operation" => @operation, "status" => " 200 ", "body" => station("none")}

      assert Comparison.compare(spec(), params) == {:ok, []}
    end

    test "reports a status the spec does not document" do
      params = %{"operation" => @operation, "status" => "503", "body" => ""}

      assert {:ok, [%Drift{kind: :undocumented_status, actual: "503"}]} = Comparison.compare(spec(), params)
    end

    test "rejects input it cannot compare" do
      base = %{"operation" => @operation, "status" => "200", "body" => "{}"}

      assert Comparison.compare(spec(), %{base | "operation" => "get /nope"}) == {:error, :unknown_operation}
      assert Comparison.compare(spec(), %{base | "operation" => ""}) == {:error, :unknown_operation}
      assert Comparison.compare(spec(), %{base | "status" => "abc"}) == {:error, :invalid_status}
      assert Comparison.compare(spec(), %{base | "status" => "600"}) == {:error, :invalid_status}
      assert Comparison.compare(spec(), %{base | "body" => "{nope"}) == {:error, :body_not_json}
    end
  end

  test "every error has a sentence for the page" do
    errors = [
      :too_large,
      :not_json_or_yaml,
      :not_an_openapi_spec,
      {:unsupported_version, "3.0.3"},
      {:unsupported_version, %{}},
      :unknown_operation,
      :invalid_status,
      :body_not_json,
      {:invalid_schema, %RuntimeError{message: "bad ref"}},
      :timeout,
      :too_much_memory,
      :busy,
      {:crashed, :boom}
    ]

    for error <- errors, do: assert(is_binary(Comparison.describe_error(error)))
  end
end
