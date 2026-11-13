defmodule DriftWatch.Checker.Drift do
  @moduledoc """
  One place where a real response does not match the spec.

  `expected` is what the spec says and `actual` is what the API returned. For type drifts
  `actual` is the JSON type and not the value, so the same drift on a changing value stays
  the same drift.
  """

  @kinds [
    :missing_field,
    :wrong_type,
    :unexpected_null,
    :extra_field,
    :invalid_value,
    :undocumented_status
  ]

  @enforce_keys [:kind, :path, :expected, :actual]
  defstruct @enforce_keys

  @type kind ::
          :missing_field
          | :wrong_type
          | :unexpected_null
          | :extra_field
          | :invalid_value
          | :undocumented_status

  @type t :: %__MODULE__{kind: kind(), path: String.t(), expected: String.t(), actual: String.t()}

  @doc """
  Lists all drift kinds.
  """
  def kinds, do: @kinds

  @doc """
  Builds a drift.
  """
  def new(kind, path, expected, actual) when kind in @kinds do
    %__MODULE__{kind: kind, path: path, expected: expected, actual: actual}
  end

  @doc """
  Names the JSON type of a decoded value.

      iex> DriftWatch.Checker.Drift.json_type(12.5)
      "number"

  """
  def json_type(nil), do: "null"
  def json_type(value) when is_boolean(value), do: "boolean"
  def json_type(value) when is_integer(value), do: "integer"
  def json_type(value) when is_float(value), do: "number"
  def json_type(value) when is_binary(value), do: "string"
  def json_type(value) when is_list(value), do: "array"
  def json_type(value) when is_map(value), do: "object"
end
