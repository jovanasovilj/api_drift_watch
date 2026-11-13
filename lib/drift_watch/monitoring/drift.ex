defmodule DriftWatch.Monitoring.Drift do
  @moduledoc """
  A distinct drift of one check, with when we saw it first and last.

  Runs link to the drifts they saw through `run_drifts`. When a run sees a drift that is
  already known, the existing row gets a new `last_seen_at` instead of a new row, so the
  history answers "since when is this broken" without scanning every run.
  """

  use Ecto.Schema

  alias DriftWatch.Checker
  alias DriftWatch.Monitoring.Check

  schema "drifts" do
    field :kind, Ecto.Enum, values: Checker.Drift.kinds()
    field :path, :string
    field :expected, :string
    field :actual, :string
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :seen_count, :integer, default: 1

    belongs_to :check, Check
  end
end
