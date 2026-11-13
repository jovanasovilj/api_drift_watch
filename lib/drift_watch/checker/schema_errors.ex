defmodule DriftWatch.Checker.SchemaErrors do
  @moduledoc """
  Turns JSV validation errors into drifts.

  JSV reports one entry per schema location that failed. Most entries only say that a child
  failed (`properties`, `items`, `$ref`), so we skip those and keep the leaf errors. Errors
  under `allOf` come nested and all of them count.

    * `required` becomes `missing_field`
    * `type` becomes `unexpected_null` when the value is null and `wrong_type` otherwise
    * value rules like `enum`, `minimum` or `pattern` become `invalid_value`

  For `oneOf` and `anyOf` every branch reports its own errors. Reporting all of them would
  blame the response for branches it never meant to match, so we pick one branch: first we
  drop branches where the value has the wrong type altogether, then we take the branch with
  the fewest drifts.
  """

  alias DriftWatch.Checker.Drift
  alias DriftWatch.JsonPointer
  alias DriftWatch.Specs

  @value_kinds [
    :const,
    :enum,
    :exclusiveMaximum,
    :exclusiveMinimum,
    :format,
    :maximum,
    :maxContains,
    :maxItems,
    :maxLength,
    :maxProperties,
    :minimum,
    :minContains,
    :minItems,
    :minLength,
    :minProperties,
    :multipleOf,
    :not,
    :pattern,
    :uniqueItems,
    :dependentRequired
  ]

  @doc """
  Returns the drifts for a JSV error, the response body and the schema document it was
  validated against.
  """
  def to_drifts(%JSV.ValidationError{} = error, body, document) do
    %{details: units} = JSV.normalize_error(error)
    Enum.flat_map(units, &unit_drifts(&1, body, document))
  end

  defp unit_drifts(unit, body, document) do
    Enum.flat_map(unit.errors, &error_drifts(&1, unit, body, document))
  end

  defp error_drifts(%{kind: :required, ctx: %{missing: names}}, unit, _body, _document) do
    for name <- names do
      Drift.new(:missing_field, JsonPointer.append(unit.instanceLocation, name), "required", "missing")
    end
  end

  defp error_drifts(%{kind: :type}, unit, body, document) do
    actual = value_at(body, unit.instanceLocation)
    kind = if is_nil(actual), do: :unexpected_null, else: :wrong_type
    expected = document |> schema_at(unit.schemaLocation) |> Map.get("type") |> type_name()

    [Drift.new(kind, unit.instanceLocation, expected, Drift.json_type(actual))]
  end

  defp error_drifts(%{kind: kind} = error, unit, body, document) when kind in [:oneOf, :anyOf] do
    error
    |> Map.get(:details, [])
    |> best_branch(unit, kind, body, document)
  end

  defp error_drifts(%{kind: kind}, unit, body, document) when kind in @value_kinds do
    rule = Atom.to_string(kind)
    limit = document |> schema_at(unit.schemaLocation) |> Map.get(rule)
    actual = value_at(body, unit.instanceLocation)

    [Drift.new(:invalid_value, unit.instanceLocation, "#{rule} #{Jason.encode!(limit)}", Jason.encode!(actual))]
  end

  # allOf and other keywords that nest errors: every nested error counts.
  defp error_drifts(%{details: units}, _unit, body, document) do
    Enum.flat_map(units, &unit_drifts(&1, body, document))
  end

  defp error_drifts(_error, _unit, _body, _document), do: []

  defp best_branch(units, parent, kind, body, document) do
    prefix = "#{parent.evaluationPath}/#{kind}/"

    branches =
      units
      |> Enum.group_by(&branch_index(&1.evaluationPath, prefix))
      |> Enum.reject(fn {index, _units} -> is_nil(index) end)
      |> Enum.map(fn {index, branch_units} ->
        drifts = Enum.flat_map(branch_units, &unit_drifts(&1, body, document))
        {index, drifts, type_mismatch?(drifts, parent.instanceLocation)}
      end)

    case Enum.reject(branches, fn {_index, _drifts, mismatch?} -> mismatch? end) do
      [] -> merge_type_mismatches(branches)
      candidates -> candidates |> Enum.min_by(fn {index, drifts, _} -> {length(drifts), index} end) |> elem(1)
    end
  end

  defp branch_index(evaluation_path, prefix) do
    with ^prefix <> rest <- evaluation_path,
         {index, _rest} <- Integer.parse(rest) do
      index
    else
      _ -> nil
    end
  end

  defp type_mismatch?(drifts, location) do
    Enum.any?(drifts, &(&1.path == location and &1.kind in [:wrong_type, :unexpected_null]))
  end

  # The value matches no branch type, for example a string where the spec allows an object or
  # null. One drift that lists every allowed type says more than one drift per branch.
  defp merge_type_mismatches([]), do: []

  defp merge_type_mismatches(branches) do
    [first | _] = mismatches = for {_index, drifts, _} <- Enum.sort(branches), drift <- drifts, do: drift
    expected = mismatches |> Enum.map(& &1.expected) |> Enum.uniq() |> Enum.join(" or ")

    [%{first | expected: expected}]
  end

  defp value_at(body, location) do
    case JsonPointer.fetch(body, location) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp schema_at(document, location) do
    case JsonPointer.fetch(document, location) do
      {:ok, schema} -> document |> Specs.resolve(schema) |> as_map()
      :error -> %{}
    end
  end

  defp as_map(%{} = schema), do: schema
  defp as_map(_schema), do: %{}

  defp type_name(types) when is_list(types), do: Enum.join(types, " or ")
  defp type_name(type) when is_binary(type), do: type
  defp type_name(_type), do: "unknown"
end
