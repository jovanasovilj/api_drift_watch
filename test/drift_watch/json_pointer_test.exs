defmodule DriftWatch.JsonPointerTest do
  use ExUnit.Case, async: true

  alias DriftWatch.JsonPointer

  doctest JsonPointer

  @document %{"a/b" => %{"c~d" => 1}, "list" => [%{"x" => nil}], "weird key" => true}

  test "the root pointer returns the whole document" do
    assert JsonPointer.fetch(@document, "#") == {:ok, @document}
  end

  test "reads escaped and percent encoded segments" do
    assert JsonPointer.fetch(@document, "#/a~1b/c~0d") == {:ok, 1}
    assert JsonPointer.fetch(@document, "#/weird%20key") == {:ok, true}
  end

  test "reads list items and keeps null values" do
    assert JsonPointer.fetch(@document, "#/list/0/x") == {:ok, nil}
  end

  test "returns :error when nothing is there" do
    assert JsonPointer.fetch(@document, "#/list/1") == :error
    assert JsonPointer.fetch(@document, "#/list/first") == :error
    assert JsonPointer.fetch(@document, "#/missing") == :error
    assert JsonPointer.fetch(@document, "/no/hash") == :error
  end

  test "append escapes what fetch unescapes" do
    pointer = "#" |> JsonPointer.append("a/b") |> JsonPointer.append("c~d")

    assert pointer == "#/a~1b/c~0d"
    assert JsonPointer.fetch(@document, pointer) == {:ok, 1}
  end
end
