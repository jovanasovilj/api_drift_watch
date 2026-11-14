defmodule DriftWatch.CheckerTest do
  use ExUnit.Case, async: true

  alias DriftWatch.Checker
  alias DriftWatch.Checker.Drift
  alias DriftWatch.Fixtures
  alias DriftWatch.Specs

  @library Fixtures.library_spec()

  @book %{
    "id" => 1,
    "title" => "Dune",
    "pages" => 412,
    "author" => %{"name" => "Frank Herbert", "born" => 1920},
    "genres" => ["science fiction"],
    "metadata" => %{"isbn" => "9780441013593", "edition" => 1}
  }

  defp compare(method, path, status, body) do
    {:ok, operation} = Specs.operation(@library, method, path)
    {:ok, drifts} = Checker.compare(@library, operation, status, body)
    drifts
  end

  defp compare_book(overrides), do: compare("get", "/books/{id}", 200, Map.merge(@book, overrides))

  defp drift(kind, path, expected, actual), do: Drift.new(kind, path, expected, actual)

  describe "compare/4 with a documented status" do
    test "a response that follows the spec has no drifts" do
      assert compare_book(%{}) == []
    end

    test "fields from every allOf branch and free form metadata are documented" do
      assert compare_book(%{"created_at" => "2026-11-13T10:00:00Z", "metadata" => %{"anything" => true}}) == []
    end

    test "null is fine where the spec allows it" do
      assert compare_book(%{"author" => nil}) == []
    end

    test "reports a missing required field" do
      body = Map.delete(@book, "title")

      assert compare("get", "/books/{id}", 200, body) == [drift(:missing_field, "#/title", "required", "missing")]
    end

    test "reports a wrong type with the type the spec expects" do
      assert compare_book(%{"pages" => "412"}) == [drift(:wrong_type, "#/pages", "integer", "string")]
    end

    test "reports null where the spec does not allow it" do
      assert compare_book(%{"title" => nil}) == [drift(:unexpected_null, "#/title", "string", "null")]
    end

    test "reports a value that breaks a rule of the schema" do
      assert compare_book(%{"pages" => 0}) == [drift(:invalid_value, "#/pages", "minimum 1", "0")]
    end

    test "reports fields the spec never mentions" do
      assert compare_book(%{"isbn" => "9780441013593"}) == [
               drift(:extra_field, "#/isbn", "not in spec", "string")
             ]
    end

    test "for oneOf it reports the errors of the closest branch" do
      assert compare_book(%{"author" => %{"born" => "1920", "alias" => "FH"}}) == [
               drift(:extra_field, "#/author/alias", "not in spec", "string"),
               drift(:wrong_type, "#/author/born", "integer", "string"),
               drift(:missing_field, "#/author/name", "required", "missing")
             ]
    end

    test "for oneOf without any matching type it lists every allowed type" do
      assert compare_book(%{"author" => "Frank Herbert"}) == [
               drift(:wrong_type, "#/author", "object or null", "string")
             ]
    end

    test "reports drift inside arrays with the index in the path" do
      second = Map.merge(@book, %{"genres" => ["classic", 7], "subtitle" => "Book one"})

      assert compare("get", "/books", 200, [@book, second]) == [
               drift(:wrong_type, "#/1/genres/1", "string", "integer"),
               drift(:extra_field, "#/1/subtitle", "not in spec", "string")
             ]
    end

    test "a body that is not JSON is a wrong type at the root" do
      assert compare("get", "/books/{id}", 200, "<html>Oops</html>") == [
               drift(:wrong_type, "#", "object", "string")
             ]
    end
  end

  describe "compare/5 with schemas that reference each other by $id" do
    setup do
      spec = Fixtures.json!("id_refs_openapi.json")
      {:ok, operation} = Specs.operation(spec, "get", "/pets/{id}")
      %{spec: spec, operation: operation}
    end

    test "resolves relative $id references against the spec URL", %{spec: spec, operation: operation} do
      body = %{"name" => "Rex", "stock" => 0, "details" => %{"id" => "seven"}}

      expected = [
        drift(:wrong_type, "#/details/id", "integer", "string"),
        drift(:invalid_value, "#/stock", "exclusiveMinimum 1", "0")
      ]

      assert {:ok, ^expected} = Checker.compare(spec, operation, 200, body, "https://pets.test/api/openapi.json")
    end

    test "works without a known spec URL", %{spec: spec, operation: operation} do
      body = %{"name" => "Rex", "details" => %{"id" => "seven"}}

      assert {:ok, [%Drift{kind: :wrong_type, path: "#/details/id"}]} = Checker.compare(spec, operation, 200, body)
    end
  end

  describe "compare/4 status lookup" do
    test "reports a status the spec does not document" do
      assert compare("get", "/books/{id}", 418, %{}) == [
               drift(:undocumented_status, "#", "200, 404, 5XX", "418")
             ]
    end

    test "uses a range like 5XX when there is no exact match" do
      assert compare("get", "/books/{id}", 503, %{"title" => "Busy"}) == []
      assert compare("get", "/books/{id}", 503, %{}) == [drift(:missing_field, "#/title", "required", "missing")]
    end

    test "follows a response that is a reference" do
      assert compare("get", "/books/{id}", 404, %{"title" => "Not found", "status" => 404}) == []
      assert compare("get", "/books/{id}", 404, %{"title" => 404}) == [drift(:wrong_type, "#/title", "string", "integer")]
    end

    test "uses default when nothing else matches" do
      assert compare("delete", "/books/{id}", 409, %{"title" => "Conflict"}) == []
    end

    test "a documented status without a body schema has nothing to compare" do
      assert compare("delete", "/books/{id}", 204, "") == []
    end
  end

  describe "run/3" do
    @api %{base_url: "https://library.test", spec_url: "https://library.test/openapi.json", spec: @library}

    test "fills path params, sends the rest as query params and compares the response" do
      Req.Test.stub(DriftWatch.HTTP, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/books/7"
        assert conn.query_string == "expand=author"

        Req.Test.json(conn, Map.delete(@book, "pages"))
      end)

      check = %{method: "GET", path: "/books/{id}", params: %{"id" => 7, "expand" => "author"}}

      assert {:ok, result} = Checker.run(@api, check)
      assert result.status == 200
      assert result.body["title"] == "Dune"
      assert is_integer(result.duration_ms)
      assert result.drifts == [drift(:missing_field, "#/pages", "required", "missing")]
    end

    test "reports the status the API answered with" do
      Req.Test.stub(DriftWatch.HTTP, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"title" => "Slow down"})
      end)

      check = %{method: "get", path: "/books/{id}", params: %{"id" => 1}}

      assert {:ok, %{status: 429, drifts: [%Drift{kind: :undocumented_status}]}} = Checker.run(@api, check)
    end

    test "returns transport errors without drifts" do
      Req.Test.stub(DriftWatch.HTTP, &Req.Test.transport_error(&1, :econnrefused))
      check = %{method: "get", path: "/books", params: %{}}

      assert {:error, %Req.TransportError{reason: :econnrefused}} = Checker.run(@api, check)
    end

    test "refuses a check without all path params" do
      check = %{method: "get", path: "/books/{id}", params: %{}}

      assert Checker.run(@api, check) == {:error, {:missing_path_params, ["id"]}}
    end

    test "refuses an operation that is not in the spec" do
      check = %{method: "post", path: "/books", params: %{}}

      assert Checker.run(@api, check) == {:error, :unknown_operation}
    end
  end
end
