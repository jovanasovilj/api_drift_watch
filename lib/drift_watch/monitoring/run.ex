defmodule DriftWatch.Monitoring.Run do
  @moduledoc """
  One call of a check. Runs are never changed after they are stored.

  A run that could not reach the API or compare its response has an `error` and no status.
  """

  use Ecto.Schema

  alias DriftWatch.Monitoring.Check
  alias DriftWatch.Monitoring.Drift

  schema "runs" do
    field :status, :integer
    field :duration_ms, :integer
    field :error, :string
    field :response_sample, :string

    belongs_to :check, Check
    many_to_many :drifts, Drift, join_through: "run_drifts"

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
