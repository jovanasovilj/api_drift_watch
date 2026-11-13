defmodule DriftWatch.Monitoring do
  @moduledoc """
  Watched APIs, their checks, the runs of those checks and the drift history.

  This is the only module that the web layer and the workers use to read or write this
  data. Every recorded run is broadcast on PubSub so the dashboard updates live.
  """

  import Ecto.Query

  alias DriftWatch.Checker
  alias DriftWatch.Monitoring.Api
  alias DriftWatch.Monitoring.Check
  alias DriftWatch.Monitoring.Drift
  alias DriftWatch.Monitoring.Run
  alias DriftWatch.Repo
  alias DriftWatch.Specs

  @topic "runs"
  @spec_max_age_hours 24
  @sample_limit 4_000
  @schedule_grace_seconds 30

  ## APIs and checks

  @doc """
  Creates an API.
  """
  def create_api(attrs) do
    %Api{}
    |> Api.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a check.
  """
  def create_check(attrs) do
    %Check{}
    |> Check.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a check with its API or `nil`.
  """
  def get_check(id) do
    Check
    |> Repo.get(id)
    |> Repo.preload(:api)
  end

  @doc """
  Gets a check with its API or raises.
  """
  def get_check!(id) do
    Check
    |> Repo.get!(id)
    |> Repo.preload(:api)
  end

  @doc """
  Returns the API with a spec that is at most a day old, downloading it when needed.
  """
  def ensure_spec(%Api{} = api, now \\ DateTime.utc_now(:second)) do
    if fresh_spec?(api, now) do
      {:ok, api}
    else
      with {:ok, spec} <- Specs.fetch(api.spec_url) do
        api
        |> Api.spec_changeset(spec, now)
        |> Repo.update()
      end
    end
  end

  defp fresh_spec?(%Api{spec: nil}, _now), do: false
  defp fresh_spec?(%Api{spec_fetched_at: nil}, _now), do: false
  defp fresh_spec?(api, now), do: DateTime.diff(now, api.spec_fetched_at, :hour) < @spec_max_age_hours

  ## Scheduling

  @doc """
  Lists the enabled checks that never ran or whose interval has passed since the last run.

  The scheduler ticks once a minute and a run finishes a little after the tick. Without some
  grace a check that ran at 12:00:02 would not be due at 12:05:00 and would wait until
  12:06:00, so every interval would grow by a minute.
  """
  def due_checks(now \\ DateTime.utc_now(:second)) do
    cutoff = DateTime.shift(now, second: @schedule_grace_seconds)

    Repo.all(
      from c in Check,
        where: c.enabled,
        where:
          is_nil(c.last_run_at) or
            fragment("? + make_interval(mins => ?) <= ?", c.last_run_at, c.interval_minutes, ^cutoff),
        order_by: c.id
    )
  end

  ## Runs and drifts

  @doc """
  Stores the result of `DriftWatch.Checker.run/3` as a run and updates the drift history.

  Drifts seen before get a new `last_seen_at` and a higher `seen_count`. New drifts get a
  new row. Both are linked to the run.
  """
  def record_run(%Check{} = check, result, now \\ DateTime.utc_now(:second)) do
    transaction =
      Repo.transact(fn ->
        run = Repo.insert!(run_from_result(check, result, now))
        drift_links = Enum.map(drifts_from_result(result), &%{run_id: run.id, drift_id: upsert_drift!(check, &1, now)})

        Repo.insert_all("run_drifts", drift_links)
        Repo.update!(Ecto.Changeset.change(check, last_run_at: now))

        {:ok, run}
      end)

    with {:ok, run} <- transaction do
      Phoenix.PubSub.broadcast(DriftWatch.PubSub, @topic, {:run_recorded, check.id, run.id})
      {:ok, run}
    end
  end

  defp run_from_result(check, {:ok, result}, now) do
    %Run{
      check_id: check.id,
      status: result.status,
      duration_ms: result.duration_ms,
      response_sample: sample(result.body),
      inserted_at: now
    }
  end

  defp run_from_result(check, {:error, reason}, now) do
    %Run{check_id: check.id, error: describe_error(reason), inserted_at: now}
  end

  defp drifts_from_result({:ok, %{drifts: drifts}}), do: drifts
  defp drifts_from_result({:error, _reason}), do: []

  defp upsert_drift!(check, %Checker.Drift{} = drift, now) do
    row = %Drift{
      check_id: check.id,
      kind: drift.kind,
      path: drift.path,
      expected: drift.expected,
      actual: drift.actual,
      first_seen_at: now,
      last_seen_at: now
    }

    %Drift{id: id} =
      Repo.insert!(row,
        on_conflict: [set: [last_seen_at: now], inc: [seen_count: 1]],
        conflict_target: [:check_id, :kind, :path, :expected, :actual],
        returning: [:id]
      )

    id
  end

  defp sample(body) when is_binary(body) do
    if String.valid?(body), do: String.slice(body, 0, @sample_limit), else: "#{byte_size(body)} bytes of binary data"
  end

  defp sample(body), do: body |> Jason.encode!(pretty: true) |> String.slice(0, @sample_limit)

  defp describe_error({:spec, reason}), do: "Could not load the spec: " <> describe_error(reason)
  defp describe_error(%{__exception__: true} = exception), do: Exception.message(exception)
  defp describe_error(reason), do: inspect(reason)

  ## Reading

  @doc """
  Returns every API with its checks and the latest run of each check.
  """
  def dashboard do
    apis = Repo.all(from a in Api, order_by: a.name, preload: [checks: ^from(c in Check, order_by: c.id)])
    latest_runs = apis |> Enum.flat_map(& &1.checks) |> Enum.map(& &1.id) |> latest_runs()

    for api <- apis do
      checks = for check <- api.checks, do: %{check: check, latest_run: latest_runs[check.id]}
      %{api: api, checks: checks}
    end
  end

  defp latest_runs(check_ids) do
    from(r in Run,
      where: r.check_id in ^check_ids,
      distinct: r.check_id,
      order_by: [asc: r.check_id, desc: r.inserted_at, desc: r.id],
      preload: [drifts: ^from(d in Drift, order_by: d.path)]
    )
    |> Repo.all()
    |> Map.new(&{&1.check_id, &1})
  end

  @doc """
  Lists the latest runs of a check, newest first, with their drifts.
  """
  def list_runs(check_id, limit \\ 25) do
    Repo.all(
      from r in Run,
        where: r.check_id == ^check_id,
        order_by: [desc: r.inserted_at, desc: r.id],
        limit: ^limit,
        preload: [drifts: ^from(d in Drift, order_by: d.path)]
    )
  end

  @doc """
  Gets a run with its drifts.
  """
  def get_run!(id) do
    Run
    |> Repo.get!(id)
    |> Repo.preload(drifts: from(d in Drift, order_by: d.path))
  end

  @doc """
  Lists the drift history of a check, most recently seen first.
  """
  def list_drifts(check_id) do
    Repo.all(from d in Drift, where: d.check_id == ^check_id, order_by: [desc: d.last_seen_at, asc: d.path])
  end

  @doc """
  Subscribes the caller to `{:run_recorded, check_id, run_id}` messages.
  """
  def subscribe, do: Phoenix.PubSub.subscribe(DriftWatch.PubSub, @topic)
end
