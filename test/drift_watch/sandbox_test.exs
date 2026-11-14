defmodule DriftWatch.SandboxTest do
  use ExUnit.Case, async: true

  alias DriftWatch.Sandbox

  test "returns what the work returns" do
    assert Sandbox.run(fn -> {:ok, 1 + 1} end) == {:ok, {:ok, 2}}
  end

  test "stops work that grows past the memory cap" do
    assert Sandbox.run(fn -> Enum.to_list(1..10_000_000) end, max_heap_bytes: 10_000_000) == {:error, :too_much_memory}
  end

  test "stops work that takes too long" do
    assert Sandbox.run(fn -> Process.sleep(:infinity) end, timeout: 50) == {:error, :timeout}
  end

  @tag :capture_log
  test "reports a crash" do
    assert {:error, {:crashed, {%RuntimeError{message: "boom"}, _stacktrace}}} = Sandbox.run(fn -> raise "boom" end)
  end

  test "refuses new work when the limit of running work is reached" do
    supervisor = start_supervised!({Task.Supervisor, max_children: 1})
    test = self()

    spawn_link(fn ->
      Sandbox.run(
        fn ->
          send(test, :running)
          Process.sleep(:infinity)
        end,
        supervisor: supervisor,
        timeout: :infinity
      )
    end)

    assert_receive :running
    assert Sandbox.run(fn -> :ok end, supervisor: supervisor) == {:error, :busy}
  end
end
