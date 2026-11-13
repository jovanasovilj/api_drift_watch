defmodule DriftWatch.Workers.CheckWorkerTest do
  use DriftWatch.DataCase, async: true
  use Oban.Testing, repo: DriftWatch.Repo

  import DriftWatch.MonitoringFixtures

  alias DriftWatch.Monitoring
  alias DriftWatch.Workers.CheckWorker

  # Requests go to this app's own endpoint, so the worker runs against the real drifty API.
  setup do
    Req.Test.stub(DriftWatch.HTTP, DriftWatchWeb.Endpoint)
    %{api: api_fixture()}
  end

  test "downloads the spec, calls the API and stores the run with its drifts", %{api: api} do
    check = check_fixture(api, %{params: %{"id" => 1, "drift" => "missing_field"}})

    assert :ok = perform_job(CheckWorker, %{check_id: check.id})

    assert [run] = Monitoring.list_runs(check.id)
    assert %{status: 200, error: nil, drifts: [%{kind: :missing_field, path: "#/name"}]} = run
    assert Monitoring.get_check!(check.id).api.spec["openapi"] == "3.1.0"
  end

  test "stores an undocumented 500 as drift and not as a failed job", %{api: api} do
    check = check_fixture(api, %{params: %{"id" => 1, "drift" => "undocumented_status"}})

    assert :ok = perform_job(CheckWorker, %{check_id: check.id})
    assert [%{status: 500, drifts: [%{kind: :undocumented_status}]}] = Monitoring.list_runs(check.id)
  end

  test "stores a spec that does not load as a run with an error", %{api: api} do
    Req.Test.stub(DriftWatch.HTTP, &Plug.Conn.send_resp(&1, 503, ""))
    check = check_fixture(api)

    assert :ok = perform_job(CheckWorker, %{check_id: check.id})
    assert [%{status: nil, error: "Could not load the spec: {:unexpected_status, 503}"}] = Monitoring.list_runs(check.id)
  end

  test "cancels the job when the check is gone" do
    assert {:cancel, :check_not_found} = perform_job(CheckWorker, %{check_id: -1})
  end

  test "queues only one job per check at a time", %{api: api} do
    check = check_fixture(api)

    assert {:ok, %{conflict?: false}} = CheckWorker.enqueue(check.id)
    assert {:ok, %{conflict?: true}} = CheckWorker.enqueue(check.id)
    assert [_job] = all_enqueued(worker: CheckWorker)
  end
end
