defmodule DriftWatch.Fixtures do
  @moduledoc """
  Loads fixture files from `test/fixtures`.
  """

  @doc """
  Reads and decodes a JSON fixture.
  """
  def json!(name) do
    __DIR__
    |> Path.join("../fixtures/#{name}")
    |> File.read!()
    |> Jason.decode!()
  end

  @doc """
  The library spec, used for the tricky schema cases.
  """
  def library_spec, do: json!("library_openapi.json")
end
