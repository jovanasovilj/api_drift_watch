defmodule DriftWatch.Checker.ExtraFields do
  @moduledoc """
  Finds response fields that the schema never mentions.

  JSON Schema allows extra properties unless a schema forbids them, so a validator does not
  report them. They still are drift: the API sends something the docs do not describe.

  We walk the response next to its schema. Properties from `allOf`, `anyOf` and `oneOf`
  branches all count as documented. An object is left alone when its schema allows extra
  fields on purpose (`additionalProperties`, `patternProperties`) or lists no properties at
  all, because then there is nothing to compare with.
  """

  alias DriftWatch.Checker.Drift
  alias DriftWatch.JsonPointer
  alias DriftWatch.Specs

  @max_depth 16

  @doc """
  Returns an `extra_field` drift for every undocumented field in `body`.
  """
  def find(body, schema, document), do: walk(body, schema, document, "#")

  defp walk(object, schema, document, path) when is_map(object) do
    schemas = expand(document, schema, 0)
    properties = documented_properties(schemas)
    open? = properties == %{} or Enum.any?(schemas, &allows_extra_fields?/1)

    object
    |> Enum.sort()
    |> Enum.flat_map(fn {key, value} ->
      value_path = JsonPointer.append(path, key)

      case Map.fetch(properties, key) do
        {:ok, value_schema} -> walk(value, value_schema, document, value_path)
        :error when open? -> []
        :error -> [Drift.new(:extra_field, value_path, "not in spec", Drift.json_type(value))]
      end
    end)
  end

  defp walk(list, schema, document, path) when is_list(list) do
    case document |> expand(schema, 0) |> Enum.find_value(&items_schema/1) do
      nil ->
        []

      items ->
        list
        |> Enum.with_index()
        |> Enum.flat_map(fn {item, index} -> walk(item, items, document, JsonPointer.append(path, index)) end)
    end
  end

  defp walk(_value, _schema, _document, _path), do: []

  # A schema plus every schema it is composed of, with references resolved.
  defp expand(_document, _schema, depth) when depth > @max_depth, do: []

  defp expand(document, schema, depth) do
    case Specs.resolve(document, schema) do
      %{} = resolved ->
        branches = Enum.flat_map(["allOf", "anyOf", "oneOf"], &List.wrap(resolved[&1]))
        [resolved | Enum.flat_map(branches, &expand(document, &1, depth + 1))]

      _boolean_schema ->
        []
    end
  end

  # When several branches describe the same property, the first one wins.
  defp documented_properties(schemas) do
    schemas
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn schema, properties ->
      Map.merge(properties, as_map(schema["properties"]))
    end)
  end

  defp allows_extra_fields?(schema) do
    Map.has_key?(schema, "patternProperties") or
      open_keyword?(schema, "additionalProperties") or
      open_keyword?(schema, "unevaluatedProperties")
  end

  defp open_keyword?(schema, keyword) do
    Map.has_key?(schema, keyword) and schema[keyword] != false
  end

  defp items_schema(%{"items" => items}) when is_map(items), do: items
  defp items_schema(_schema), do: nil

  defp as_map(%{} = map), do: map
  defp as_map(_value), do: %{}
end
