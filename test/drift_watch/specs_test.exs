defmodule DriftWatch.SpecsTest do
  use ExUnit.Case, async: true

  alias DriftWatch.Fixtures
  alias DriftWatch.Specs

  @library Fixtures.library_spec()

  describe "parse/1" do
    test "accepts OpenAPI 3.1 and 3.2 as a map or as JSON text" do
      assert {:ok, %{"openapi" => "3.1.0"}} = Specs.parse(@library)
      assert {:ok, %{"openapi" => "3.2.0"}} = Specs.parse(~s({"openapi": "3.2.0"}))
    end

    test "refuses other versions and other documents" do
      assert Specs.parse(%{"openapi" => "3.0.3"}) == {:error, {:unsupported_version, "3.0.3"}}
      assert Specs.parse(%{"swagger" => "2.0"}) == {:error, :not_an_openapi_spec}
      assert Specs.parse("not json") == {:error, :invalid_json}
    end
  end

  describe "fetch/2" do
    test "downloads and parses a spec" do
      Req.Test.stub(DriftWatch.HTTP, &Req.Test.json(&1, @library))

      assert Specs.fetch("https://library.test/openapi.json") == {:ok, @library}
    end

    test "parses a spec served as plain text" do
      Req.Test.stub(DriftWatch.HTTP, &Req.Test.text(&1, Jason.encode!(@library)))

      assert Specs.fetch("https://library.test/openapi.json") == {:ok, @library}
    end

    test "returns an error for a status other than 200" do
      Req.Test.stub(DriftWatch.HTTP, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(404, "Not found")
      end)

      assert Specs.fetch("https://library.test/openapi.json") == {:error, {:unexpected_status, 404}}
    end
  end

  describe "operation/3" do
    test "finds an operation by method in any case and path template" do
      assert {:ok, %{"responses" => %{"204" => _}}} = Specs.operation(@library, "DELETE", "/books/{id}")
    end

    test "returns an error for an unknown operation" do
      assert Specs.operation(@library, "get", "/authors") == {:error, :unknown_operation}
    end
  end

  describe "response_schema/3" do
    setup do
      {:ok, operation} = Specs.operation(@library, "get", "/books/{id}")
      %{operation: operation}
    end

    test "matches the exact status first", %{operation: operation} do
      assert Specs.response_schema(@library, operation, 200) == {:ok, %{"$ref" => "#/components/schemas/Book"}}
    end

    test "falls back to a range and accepts +json media types", %{operation: operation} do
      assert Specs.response_schema(@library, operation, 502) == {:ok, %{"$ref" => "#/components/schemas/Problem"}}
    end

    test "returns :undocumented for a status the spec does not mention", %{operation: operation} do
      assert Specs.response_schema(@library, operation, 301) == :undocumented
    end
  end

  describe "resolve/2" do
    test "follows references and leaves unknown ones alone" do
      assert %{"required" => ["name"]} = Specs.resolve(@library, %{"$ref" => "#/components/schemas/Author"})
      assert Specs.resolve(@library, %{"$ref" => "#/nowhere"}) == %{"$ref" => "#/nowhere"}

      assert Specs.resolve(@library, %{"$ref" => "https://example.com/x.json"}) == %{
               "$ref" => "https://example.com/x.json"
             }
    end
  end
end
