defmodule DriftWatch.Monitoring.Check do
  @moduledoc """
  One operation of an API that we call on a schedule.

  `path` is the path template from the spec, like `/stations/{id}`. `params` fills the
  template and anything left over is sent as query params.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias DriftWatch.Monitoring.Api
  alias DriftWatch.Monitoring.Drift
  alias DriftWatch.Monitoring.Run

  @methods ~w(get head options post put patch delete)

  schema "checks" do
    field :method, :string, default: "get"
    field :path, :string
    field :params, :map, default: %{}
    field :interval_minutes, :integer, default: 5
    field :enabled, :boolean, default: true
    field :last_run_at, :utc_datetime

    belongs_to :api, Api
    has_many :runs, Run
    has_many :drifts, Drift

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or editing a check.
  """
  def changeset(check, attrs) do
    check
    |> cast(attrs, [:api_id, :method, :path, :params, :interval_minutes, :enabled])
    |> update_change(:method, &String.downcase/1)
    |> validate_required([:api_id, :method, :path, :interval_minutes])
    |> validate_inclusion(:method, @methods)
    |> validate_format(:path, ~r{^/})
    |> validate_number(:interval_minutes, greater_than_or_equal_to: 1)
    |> assoc_constraint(:api)
  end
end
