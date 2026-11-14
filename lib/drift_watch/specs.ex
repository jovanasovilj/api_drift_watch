defmodule DriftWatch.Specs do
  @moduledoc """
  Loads OpenAPI specs and finds the response schema for one operation and status code.

  Specs are kept as plain maps with string keys, exactly as they come out of JSON. We never
  turn spec keys into atoms, because specs come from the internet.

  Only OpenAPI 3.1 and 3.2 are supported for now. Their schemas are JSON Schema 2020-12, which
  is what JSV validates. OpenAPI 3.0 schemas use a different dialect (`nullable` for example) and
  need a conversion step first. Specs can be JSON or YAML.
  """

  alias DriftWatch.HTTP
  alias DriftWatch.JsonPointer

  @dialect "https://json-schema.org/draft/2020-12/schema"
  @max_ref_hops 32
  @http_methods ~w(get put post delete options head patch trace)

  @doc """
  Downloads a spec and parses it with `parse/1`.
  """
  def fetch(url, req_options \\ []) do
    case Req.get(HTTP.new(req_options), url: url) do
      {:ok, %Req.Response{status: 200, body: body}} -> parse(body)
      {:ok, %Req.Response{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, exception} -> {:error, exception}
    end
  end

  @doc """
  Turns a decoded spec or raw JSON or YAML text into a map and checks that it is OpenAPI 3.1
  or 3.2.
  """
  def parse(body) when is_binary(body) do
    case decode(body) do
      {:ok, %{} = spec} -> parse(spec)
      _not_a_document -> {:error, :not_json_or_yaml}
    end
  end

  def parse(%{"openapi" => "3.1." <> _patch} = spec), do: {:ok, spec}
  def parse(%{"openapi" => "3.2." <> _patch} = spec), do: {:ok, spec}
  def parse(%{"openapi" => version}), do: {:error, {:unsupported_version, version}}
  def parse(_body), do: {:error, :not_an_openapi_spec}

  # JSON first, because it is stricter and most specs are JSON. YAML reads an unquoted `200:`
  # as the integer 200, so all keys become strings to match what JSON gives.
  defp decode(text) do
    case Jason.decode(text) do
      {:ok, spec} ->
        {:ok, spec}

      {:error, _not_json} ->
        with {:ok, spec} <- YamlElixir.read_from_string(text), do: {:ok, string_keys(spec)}
    end
  end

  defp string_keys(%{} = map), do: Map.new(map, fn {key, value} -> {to_string(key), string_keys(value)} end)
  defp string_keys(list) when is_list(list), do: Enum.map(list, &string_keys/1)
  defp string_keys(value), do: value

  @doc """
  Finds the operation for a method and a path template like `/stations/{id}`.
  """
  def operation(spec, method, path) do
    case get_in(spec, ["paths", path, String.downcase(method)]) do
      %{} = operation -> {:ok, operation}
      nil -> {:error, :unknown_operation}
    end
  end

  @doc """
  Lists every operation in the spec as `{method, path}`, sorted by path. Path items that are
  not maps and keys that are not HTTP methods, like `parameters`, are skipped.
  """
  def operations(%{"paths" => %{} = paths}) do
    for {path, %{} = item} <- Enum.sort(paths), method <- @http_methods, is_map(item[method]) do
      {method, path}
    end
  end

  def operations(_spec), do: []

  @doc """
  Finds the JSON response schema for a status code.

  Lookup order follows the OpenAPI spec: the exact code, then a range like `2XX`, then
  `default`. Returns `:no_schema` when the status is documented without a JSON body and
  `:undocumented` when the spec does not mention the status at all.
  """
  def response_schema(spec, operation, status) do
    responses = Map.get(operation, "responses", %{})
    range = "#{div(status, 100)}XX"

    case find_response(responses, [to_string(status), range, String.downcase(range), "default"]) do
      nil -> :undocumented
      response -> json_schema(resolve(spec, response))
    end
  end

  @doc """
  Lists the documented status codes of an operation, like `["200", "404"]`.
  """
  def documented_statuses(operation) do
    operation |> Map.get("responses", %{}) |> Map.keys() |> Enum.sort()
  end

  @doc """
  Wraps a response schema in a JSON Schema document that JSV can build.

  The spec components go along, so local `$ref` values like `#/components/schemas/Station`
  resolve against this document the same way they do against the spec.

  The document gets `base_uri` as its `$id`. OpenAPI 3.1 resolves relative references against
  the URL the spec was loaded from. Schemas may also declare a relative `$id` of their own, as
  the Petstore 3.1 spec does. Without a base JSV cannot place those.
  """
  def schema_document(spec, schema, base_uri \\ default_base_uri()) do
    %{
      "$schema" => @dialect,
      "$id" => base_uri,
      "$ref" => "#/$defs/response",
      "$defs" => %{"response" => schema},
      "components" => Map.get(spec, "components", %{})
    }
  end

  @doc """
  The base URI for a spec whose URL we do not know, like a fixture in a test. The `.invalid`
  domain is reserved and never resolves.
  """
  def default_base_uri, do: "https://spec.invalid/openapi.json"

  @doc """
  Follows `$ref` values until it reaches a schema without one.

  Returns the schema unchanged when a reference points outside the document, so callers
  can treat it as unknown.
  """
  def resolve(document, schema, hops \\ 0)

  def resolve(document, %{"$ref" => "#" <> _ = ref} = schema, hops) when hops < @max_ref_hops do
    case JsonPointer.fetch(document, ref) do
      {:ok, target} -> resolve(document, target, hops + 1)
      :error -> schema
    end
  end

  def resolve(_document, schema, _hops), do: schema

  defp find_response(responses, keys) do
    Enum.find_value(keys, &Map.get(responses, &1))
  end

  defp json_schema(%{"content" => content}) when is_map(content) do
    Enum.find_value(content, :no_schema, fn {media_type, media} ->
      if json_media_type?(media_type) and is_map(media["schema"]), do: {:ok, media["schema"]}
    end)
  end

  defp json_schema(_response), do: :no_schema

  defp json_media_type?(media_type) do
    String.match?(media_type, ~r{^application/([\w.-]+\+)?json\b}i)
  end
end
