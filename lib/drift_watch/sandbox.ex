defmodule DriftWatch.Sandbox do
  @moduledoc """
  Runs work on untrusted input in its own process with a memory cap and a time limit.

  The compare page parses specs that strangers paste. A few hundred bytes of YAML with nested
  aliases expand to a billion values and a schema can hold a regex that never finishes. The
  BEAM can cap the heap of a single process, so the work runs in a separate process that gets
  killed when it grows too big or takes too long. The page itself keeps running.

  At most a few of these run at the same time, so the worst case for the whole node is known.
  """

  @supervisor DriftWatch.Sandbox.Supervisor
  @timeout 5_000
  @max_heap_bytes 128_000_000
  # Tests run many comparisons in parallel, so config/test.exs raises this.
  @max_running Application.compile_env(:drift_watch, [__MODULE__, :max_running], 4)

  @doc """
  The child spec for the supervisor that runs the work. It goes in the application tree.
  """
  def child_spec(_opts) do
    Supervisor.child_spec({Task.Supervisor, name: @supervisor, max_children: @max_running}, id: __MODULE__)
  end

  def timeout, do: @timeout
  def max_heap_bytes, do: @max_heap_bytes

  @doc """
  Runs `fun` and returns `{:ok, result}`.

  Returns `{:error, :too_much_memory}`, `{:error, :timeout}` or `{:error, :busy}` when the
  work was stopped or could not start. A crash comes back as `{:error, {:crashed, reason}}`.

  The options `:supervisor`, `:timeout` and `:max_heap_bytes` exist for tests.
  """
  def run(fun, opts \\ []) when is_function(fun, 0) do
    supervisor = Keyword.get(opts, :supervisor, @supervisor)
    timeout = Keyword.get(opts, :timeout, @timeout)
    max_heap_words = div(Keyword.get(opts, :max_heap_bytes, @max_heap_bytes), :erlang.system_info(:wordsize))
    owner = self()
    reply = make_ref()

    work = fn ->
      Process.flag(:max_heap_size, %{size: max_heap_words, kill: true, error_logger: false})
      send(owner, {reply, fun.()})
    end

    case Task.Supervisor.start_child(supervisor, work) do
      {:ok, pid} -> await(pid, reply, timeout)
      {:error, :max_children} -> {:error, :busy}
    end
  end

  defp await(pid, reply, timeout) do
    monitor = Process.monitor(pid)

    receive do
      {^reply, result} ->
        Process.demonitor(monitor, [:flush])
        {:ok, result}

      {:DOWN, ^monitor, :process, ^pid, :killed} ->
        {:error, :too_much_memory}

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        {:error, {:crashed, reason}}
    after
      timeout ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor, [:flush])
        # The work may have finished right before it was killed.
        receive do
          {^reply, _late} -> :ok
        after
          0 -> :ok
        end

        {:error, :timeout}
    end
  end
end
