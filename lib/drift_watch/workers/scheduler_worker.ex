defmodule DriftWatch.Workers.SchedulerWorker do
  @moduledoc """
  Runs every minute from the Oban cron plugin and queues every check that is due.

  Deciding from the database on every tick keeps scheduling simple: a restart, a changed
  interval or a lost job fixes itself on the next minute. `CheckWorker` jobs are unique per
  check, so a check that is still running is not queued twice.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias DriftWatch.Monitoring
  alias DriftWatch.Workers.CheckWorker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    for check <- Monitoring.due_checks() do
      {:ok, _job} = CheckWorker.enqueue(check.id)
    end

    :ok
  end
end
