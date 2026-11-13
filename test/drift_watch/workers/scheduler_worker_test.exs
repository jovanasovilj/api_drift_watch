defmodule DriftWatch.Workers.SchedulerWorkerTest do
  use DriftWatch.DataCase, async: true
  use Oban.Testing, repo: DriftWatch.Repo

  import DriftWatch.MonitoringFixtures

  alias DriftWatch.Workers.CheckWorker
  alias DriftWatch.Workers.SchedulerWorker

  test "queues the checks that are due and skips the others" do
    api = api_fixture()
    due = check_fixture(api)
    recent = check_fixture(api)
    Repo.update!(Ecto.Changeset.change(recent, last_run_at: DateTime.utc_now(:second)))

    assert :ok = perform_job(SchedulerWorker, %{})

    assert_enqueued worker: CheckWorker, args: %{check_id: due.id}
    refute_enqueued worker: CheckWorker, args: %{check_id: recent.id}
  end
end
