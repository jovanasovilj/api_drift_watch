defmodule DriftWatch.Checker do
  @moduledoc """
  Calls an endpoint and compares the real response with its spec.

  `compare/4` holds all the logic and does no IO, so tests feed it fixture responses.
  `run/3` adds the HTTP call and the timing around it.

  A check names its operation with the path template from the spec, like
  `/stations/{id}`, plus the params to fill in. Params that are not in the template are sent
  as query params.
  """

  alias DriftWatch.Checker.Drift
  alias DriftWatch.Checker.ExtraFields
  alias DriftWatch.Checker.SchemaErrors
  alias DriftWatch.HTTP
  alias DriftWatch.Specs

  @methods %{
    "get" => :get,
    "head" => :head,
    "options" => :options,
    "post" => :post,
    "put" => :put,
    "patch" => :patch,
    "delete" => :delete
  }

  @path_param ~r/\{([^}]+)\}/

  @doc """
  Calls the endpoint of `check` on `api` and compares the response with the spec.

  `api` needs `:base_url`, `:spec_url` and a parsed `:spec`. `check` needs `:method`, `:path`
  and `:params`. Returns the status, the duration in milliseconds, the decoded body and the
  drifts.
  """
  def run(api, check, req_options \\ []) do
    with {:ok, method} <- fetch_method(check.method),
         {:ok, operation} <- Specs.operation(api.spec, check.method, check.path),
         {:ok, path, query} <- fill_path(check.path, check.params || %{}),
         {:ok, response, duration_ms} <- request(api.base_url, method, path, query, req_options),
         {:ok, drifts} <- compare(api.spec, operation, response.status, response.body, api.spec_url) do
      {:ok, %{status: response.status, duration_ms: duration_ms, body: response.body, drifts: drifts}}
    end
  end

  @doc """
  Compares a status code and a decoded body with what the operation documents.

  Drifts come back sorted by path, so the same response always gives the same list.
  `base_uri` is the URL the spec came from, see `DriftWatch.Specs.schema_document/3`.
  """
  def compare(spec, operation, status, body, base_uri \\ Specs.default_base_uri()) do
    case Specs.response_schema(spec, operation, status) do
      :undocumented ->
        documented = operation |> Specs.documented_statuses() |> Enum.join(", ")
        {:ok, [Drift.new(:undocumented_status, "#", documented, to_string(status))]}

      :no_schema ->
        {:ok, []}

      {:ok, schema} ->
        document = Specs.schema_document(spec, schema, base_uri)

        with {:ok, schema_drifts} <- validate(body, document) do
          drifts = schema_drifts ++ ExtraFields.find(body, schema, document)
          {:ok, drifts |> Enum.uniq() |> Enum.sort_by(&{&1.path, &1.kind})}
        end
    end
  end

  defp validate(body, document) do
    case JSV.build(document) do
      {:ok, root} ->
        case JSV.validate(body, root) do
          {:ok, _casted} -> {:ok, []}
          {:error, error} -> {:ok, SchemaErrors.to_drifts(error, body, document)}
        end

      {:error, build_error} ->
        {:error, {:invalid_schema, build_error}}
    end
  end

  defp fetch_method(method) do
    case Map.fetch(@methods, String.downcase(method)) do
      {:ok, atom} -> {:ok, atom}
      :error -> {:error, {:unsupported_method, method}}
    end
  end

  defp fill_path(template, params) do
    names = @path_param |> Regex.scan(template, capture: :all_but_first) |> List.flatten()

    case Enum.reject(names, &Map.has_key?(params, &1)) do
      [] ->
        path = Regex.replace(@path_param, template, fn _match, name -> encode_segment(params[name]) end)
        {:ok, path, Map.drop(params, names)}

      missing ->
        {:error, {:missing_path_params, missing}}
    end
  end

  defp encode_segment(value), do: value |> to_string() |> URI.encode(&URI.char_unreserved?/1)

  defp request(base_url, method, path, query, req_options) do
    request = HTTP.new(req_options)
    started_at = System.monotonic_time()
    result = Req.request(request, method: method, base_url: base_url, url: path, params: query)
    duration_ms = System.convert_time_unit(System.monotonic_time() - started_at, :native, :millisecond)

    case result do
      {:ok, response} -> {:ok, response, duration_ms}
      {:error, exception} -> {:error, exception}
    end
  end
end
