defmodule DriftWatch.MonitoringTest do
  use DriftWatch.DataCase, async: true

  import DriftWatch.MonitoringFixtures

  alias DriftWatch.Checker.Drift
  alias DriftWatch.Drifty
  alias DriftWatch.Monitoring

  @now ~U[2026-11-13 12:00:00Z]

  defp ok_result(drifts), do: {:ok, %{status: 200, duration_ms: 12, body: %{"id" => 1}, drifts: drifts}}

  defp minutes_ago(minutes), do: DateTime.shift(@now, minute: -minutes)

  setup do
    api = api_fixture()
    %{api: api, check: check_fixture(api)}
  end

  describe "record_run/3" do
    test "stores the run with its drifts and marks when the check ran", %{check: check} do
      drift = Drift.new(:missing_field, "#/name", "required", "missing")

      assert {:ok, run} = Monitoring.record_run(check, ok_result([drift]), @now)

      run = Monitoring.get_run!(run.id)
      assert %{status: 200, duration_ms: 12, error: nil, inserted_at: @now} = run
      assert Jason.decode!(run.response_sample) == %{"id" => 1}
      assert [%{kind: :missing_field, path: "#/name", first_seen_at: @now, seen_count: 1}] = run.drifts
      assert Monitoring.get_check!(check.id).last_run_at == @now
    end

    test "a drift seen again updates the same history row", %{check: check} do
      drift = Drift.new(:wrong_type, "#/temperature_c", "number", "string")
      later = DateTime.shift(@now, minute: 1)

      {:ok, first} = Monitoring.record_run(check, ok_result([drift]), @now)
      {:ok, second} = Monitoring.record_run(check, ok_result([drift]), later)

      assert [history] = Monitoring.list_drifts(check.id)
      assert %{first_seen_at: @now, last_seen_at: ^later, seen_count: 2} = history
      assert [%{id: id}] = Monitoring.get_run!(first.id).drifts
      assert [%{id: ^id}] = Monitoring.get_run!(second.id).drifts
    end

    test "a clean run keeps the history and links no drifts", %{check: check} do
      drift = Drift.new(:extra_field, "#/humidity_pct", "not in spec", "integer")
      {:ok, _first} = Monitoring.record_run(check, ok_result([drift]), @now)
      {:ok, clean} = Monitoring.record_run(check, ok_result([]), DateTime.shift(@now, minute: 1))

      assert Monitoring.get_run!(clean.id).drifts == []
      assert [%{last_seen_at: @now}] = Monitoring.list_drifts(check.id)
    end

    test "stores an error as a run without status", %{check: check} do
      error = {:error, %Req.TransportError{reason: :timeout}}

      assert {:ok, run} = Monitoring.record_run(check, error, @now)
      assert %{status: nil, error: "timeout"} = run
    end

    test "describes a spec that could not be loaded", %{check: check} do
      assert {:ok, run} = Monitoring.record_run(check, {:error, {:spec, {:unexpected_status, 404}}}, @now)
      assert run.error == "Could not load the spec: {:unexpected_status, 404}"
    end

    test "broadcasts every recorded run", %{check: check} do
      Monitoring.subscribe()
      {:ok, run} = Monitoring.record_run(check, ok_result([]), @now)

      assert_receive {:run_recorded, check_id, run_id}
      assert {check_id, run_id} == {check.id, run.id}
    end
  end

  describe "due_checks/1" do
    test "returns enabled checks that never ran or whose interval passed", %{api: api, check: never_ran} do
      due = check_fixture(api, %{interval_minutes: 5})
      finished_late = check_fixture(api, %{interval_minutes: 5})
      not_due = check_fixture(api, %{interval_minutes: 5})
      disabled = check_fixture(api, %{enabled: false})

      Repo.update!(Ecto.Changeset.change(due, last_run_at: minutes_ago(5)))
      Repo.update!(Ecto.Changeset.change(finished_late, last_run_at: DateTime.shift(minutes_ago(5), second: 20)))
      Repo.update!(Ecto.Changeset.change(not_due, last_run_at: minutes_ago(4)))

      ids = @now |> Monitoring.due_checks() |> Enum.map(& &1.id)

      assert ids == [never_ran.id, due.id, finished_late.id]
      refute disabled.id in ids
    end
  end

  describe "ensure_spec/2" do
    test "downloads a missing spec and stores it", %{api: api} do
      Req.Test.stub(DriftWatch.HTTP, fn conn ->
        assert conn.request_path == "/drifty/openapi.json"
        Req.Test.text(conn, Drifty.spec_json())
      end)

      assert {:ok, %{spec: %{"openapi" => "3.1.0"}, spec_fetched_at: @now}} = Monitoring.ensure_spec(api, @now)
    end

    test "keeps a spec that is less than a day old", %{api: api} do
      api = Repo.update!(Ecto.Changeset.change(api, spec: %{"openapi" => "3.1.0"}, spec_fetched_at: minutes_ago(60)))
      Req.Test.stub(DriftWatch.HTTP, fn _conn -> flunk("the spec should not be downloaded again") end)

      assert Monitoring.ensure_spec(api, @now) == {:ok, api}
    end

    test "downloads a spec again after a day", %{api: api} do
      api = Repo.update!(Ecto.Changeset.change(api, spec: %{"openapi" => "3.1.0"}, spec_fetched_at: minutes_ago(25 * 60)))
      Req.Test.stub(DriftWatch.HTTP, &Req.Test.text(&1, Drifty.spec_json()))

      assert {:ok, %{spec_fetched_at: @now, spec: %{"paths" => %{}}}} = Monitoring.ensure_spec(api, @now)
    end
  end

  describe "dashboard/0" do
    test "returns every check with its latest run", %{api: api, check: check} do
      idle = check_fixture(api)
      {:ok, _old} = Monitoring.record_run(check, ok_result([]), @now)
      {:ok, latest} = Monitoring.record_run(check, {:error, :boom}, DateTime.shift(@now, minute: 1))

      assert [%{api: %{id: api_id}, checks: [first, second]}] = Monitoring.dashboard()
      assert api_id == api.id
      assert {first.check.id, first.latest_run.id} == {check.id, latest.id}
      assert {second.check.id, second.latest_run} == {idle.id, nil}
    end
  end
end
