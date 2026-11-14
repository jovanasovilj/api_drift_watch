defmodule DriftWatch.Monitoring.Api do
  @moduledoc """
  A watched API with its spec. The spec is cached here so a check does not download it on
  every run.

  Specs can be large (GitHub's is about 14 MB), so the `spec` column is not loaded by normal
  queries. `DriftWatch.Monitoring.ensure_spec/2` reads it when a check needs it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias DriftWatch.Monitoring.Check

  schema "apis" do
    field :name, :string
    field :base_url, :string
    field :spec_url, :string
    field :spec, :map, load_in_query: false
    field :spec_fetched_at, :utc_datetime

    has_many :checks, Check

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or editing an API.
  """
  def changeset(api, attrs) do
    api
    |> cast(attrs, [:name, :base_url, :spec_url])
    |> validate_required([:name, :base_url, :spec_url])
    |> validate_url(:base_url)
    |> validate_url(:spec_url)
    |> unique_constraint(:name)
  end

  @doc """
  Changeset for storing a freshly fetched spec.
  """
  def spec_changeset(api, spec, fetched_at) do
    change(api, spec: spec, spec_fetched_at: fetched_at)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn ^field, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> []
        _uri -> [{field, "must be an http or https URL"}]
      end
    end)
  end
end
