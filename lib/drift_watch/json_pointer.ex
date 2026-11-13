defmodule DriftWatch.JsonPointer do
  @moduledoc """
  Reads values from decoded JSON with pointers in URI fragment form, like `#/location/lat`.

  This is the form JSV uses for error locations and OpenAPI uses for local `$ref` values.
  """

  @doc """
  Returns `{:ok, value}` for the value at `pointer` or `:error` when nothing is there.

      iex> DriftWatch.JsonPointer.fetch(%{"tags" => ["a", "b"]}, "#/tags/1")
      {:ok, "b"}

  """
  def fetch(document, "#" <> pointer), do: fetch_segments(document, segments(pointer))
  def fetch(_document, _pointer), do: :error

  @doc """
  Adds one segment to a pointer and escapes it.

      iex> DriftWatch.JsonPointer.append("#/location", "lat")
      "#/location/lat"

  """
  def append(pointer, segment) do
    escaped =
      segment
      |> to_string()
      |> String.replace("~", "~0")
      |> String.replace("/", "~1")

    pointer <> "/" <> escaped
  end

  defp segments(""), do: []

  defp segments("/" <> pointer) do
    pointer
    |> String.split("/")
    |> Enum.map(&unescape/1)
  end

  defp unescape(segment) do
    segment
    |> URI.decode()
    |> String.replace("~1", "/")
    |> String.replace("~0", "~")
  end

  defp fetch_segments(value, []), do: {:ok, value}

  defp fetch_segments(map, [key | rest]) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> fetch_segments(value, rest)
      :error -> :error
    end
  end

  defp fetch_segments(list, [index | rest]) when is_list(list) do
    case Integer.parse(index) do
      {position, ""} when position >= 0 and position < length(list) ->
        list |> Enum.at(position) |> fetch_segments(rest)

      _ ->
        :error
    end
  end

  defp fetch_segments(_value, _segments), do: :error
end
