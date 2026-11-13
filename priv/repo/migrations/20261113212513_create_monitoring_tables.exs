defmodule DriftWatch.Repo.Migrations.CreateMonitoringTables do
  use Ecto.Migration

  def change do
    create table(:apis) do
      add :name, :string, null: false
      add :base_url, :string, null: false
      add :spec_url, :string, null: false
      add :spec, :map
      add :spec_fetched_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:apis, [:name])

    create table(:checks) do
      add :api_id, references(:apis, on_delete: :delete_all), null: false
      add :method, :string, null: false
      add :path, :string, null: false
      add :params, :map, null: false, default: %{}
      add :interval_minutes, :integer, null: false, default: 5
      add :enabled, :boolean, null: false, default: true
      add :last_run_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:checks, [:api_id])

    create table(:runs) do
      add :check_id, references(:checks, on_delete: :delete_all), null: false
      add :status, :integer
      add :duration_ms, :integer
      add :error, :text
      add :response_sample, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:runs, [:check_id, :inserted_at])

    create table(:drifts) do
      add :check_id, references(:checks, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :path, :text, null: false
      add :expected, :text, null: false
      add :actual, :text, null: false
      add :first_seen_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false
      add :seen_count, :integer, null: false, default: 1
    end

    # One row per distinct drift of a check, so a run that sees it again updates that row.
    create unique_index(:drifts, [:check_id, :kind, :path, :expected, :actual])

    create table(:run_drifts, primary_key: false) do
      add :run_id, references(:runs, on_delete: :delete_all), null: false, primary_key: true
      add :drift_id, references(:drifts, on_delete: :delete_all), null: false, primary_key: true
    end

    create index(:run_drifts, [:drift_id])
  end
end
