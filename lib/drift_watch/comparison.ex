defmodule DriftWatch.Comparison do
  @moduledoc """
  Compares a pasted response with a pasted spec. This is what the compare page runs.

  It uses the same `DriftWatch.Checker.compare/4` as the scheduled checks, but nothing is
  fetched and nothing is stored. Specs and bodies come from strangers, so both are size limited
  and all parsing and comparing runs in `DriftWatch.Sandbox`.
  """

  alias DriftWatch.Checker
  alias DriftWatch.Sandbox
  alias DriftWatch.Specs

  @max_bytes 1_000_000

  @doc """
  Parses a spec and lists its operations.

  Returns `{:ok, %{spec: spec, operations: [{method, path}]}}` or `{:error, reason}`.
  """
  def load_spec(text) when byte_size(text) > @max_bytes, do: {:error, :too_large}

  def load_spec(text) when is_binary(text) do
    fn ->
      with {:ok, spec} <- Specs.parse(text) do
        {:ok, %{spec: spec, operations: Specs.operations(spec)}}
      end
    end
    |> Sandbox.run()
    |> unwrap()
  end

  @doc """
  Compares a response with a loaded spec.

  `params` holds what the form sends: `"operation"` like `"get /pets/{id}"`, `"status"` and
  `"body"` as JSON text. An empty body counts as no body. Returns `{:ok, drifts}` or
  `{:error, reason}`.
  """
  def compare(spec, %{"operation" => operation, "status" => status, "body" => body}) do
    with {:ok, method, path} <- split_operation(operation),
         {:ok, status} <- parse_status(status),
         :ok <- check_size(body) do
      unwrap(Sandbox.run(fn -> compare_untrusted(spec, method, path, status, body) end))
    end
  end

  defp compare_untrusted(spec, method, path, status, body) do
    with {:ok, operation} <- Specs.operation(spec, method, path),
         {:ok, body} <- decode_body(body) do
      Checker.compare(spec, operation, status, body)
    end
  end

  @doc """
  Turns an error from `load_spec/1` or `compare/2` into a sentence for the page.
  """
  def describe_error(:too_large), do: "This is more than 1 MB. Paste something smaller."
  def describe_error(:not_json_or_yaml), do: "This is not valid JSON or YAML."
  def describe_error(:not_an_openapi_spec), do: "This has no openapi field, so it is not an OpenAPI spec."

  def describe_error({:unsupported_version, version}) when is_binary(version) or is_number(version),
    do: "This is OpenAPI #{version}. Only 3.1 and 3.2 are supported for now."

  def describe_error({:unsupported_version, _version}), do: "The openapi field should be a version like 3.1.0."

  def describe_error(:unknown_operation), do: "Pick an operation from the spec."
  def describe_error(:invalid_status), do: "The status must be a number from 100 to 599."
  def describe_error(:body_not_json), do: "The response body is not valid JSON."

  def describe_error({:invalid_schema, error}),
    do: "The spec has a schema that cannot be built: #{Exception.message(error)}"

  def describe_error(:timeout), do: "This took longer than #{div(Sandbox.timeout(), 1000)} seconds and was stopped."

  def describe_error(:too_much_memory),
    do:
      "This needed more than #{div(Sandbox.max_heap_bytes(), 1_000_000)} MB of memory and was stopped. " <>
        "YAML aliases nested in each other do that."

  def describe_error(:busy), do: "Too many comparisons are running right now. Try again in a moment."
  def describe_error({:crashed, _reason}), do: "Part of this spec has a shape that could not be read."

  defp unwrap({:ok, {:ok, value}}), do: {:ok, value}
  defp unwrap({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap({:error, reason}), do: {:error, reason}

  defp split_operation(operation) when is_binary(operation) do
    case String.split(operation, " ", parts: 2) do
      [method, path] -> {:ok, method, path}
      _other -> {:error, :unknown_operation}
    end
  end

  defp split_operation(_operation), do: {:error, :unknown_operation}

  defp parse_status(status) when is_integer(status) and status in 100..599, do: {:ok, status}

  defp parse_status(status) when is_binary(status) do
    case Integer.parse(String.trim(status)) do
      {number, ""} -> parse_status(number)
      _other -> {:error, :invalid_status}
    end
  end

  defp parse_status(_status), do: {:error, :invalid_status}

  defp check_size(body) when is_binary(body) and byte_size(body) <= @max_bytes, do: :ok
  defp check_size(body) when is_binary(body), do: {:error, :too_large}
  defp check_size(_body), do: {:error, :body_not_json}

  defp decode_body(body) do
    if String.trim(body) == "" do
      {:ok, nil}
    else
      case Jason.decode(body) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, _error} -> {:error, :body_not_json}
      end
    end
  end
end
