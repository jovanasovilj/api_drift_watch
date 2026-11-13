defmodule DriftWatch.Workers.CheckWorker do
  @moduledoc """
  Runs one check and stores the run.

  Every outcome is stored as a run, also a timeout or a spec that does not load. Those are
  facts about the API, so the job still succeeds and Oban does not retry. A retry would hide
  exactly the flaky behaviour we want to see. The job only fails on our own bugs.

  Only one job per check can wait or run at a time, so a slow API never piles up jobs.
  """

  use Oban.Worker,
    queue: :checks,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:check_id], states: :incomplete]

  alias DriftWatch.Checker
  alias DriftWatch.Monitoring

  @doc """
  Queues a run of the check now.
  """
  def enqueue(check_id) do
    %{check_id: check_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"check_id" => check_id}}) do
    case Monitoring.get_check(check_id) do
      nil ->
        {:cancel, :check_not_found}

      check ->
        {:ok, _run} = Monitoring.record_run(check, run(check))
        :ok
    end
  end

  defp run(check) do
    case Monitoring.ensure_spec(check.api) do
      {:ok, api} -> Checker.run(api, check)
      {:error, reason} -> {:error, {:spec, reason}}
    end
  end
end
