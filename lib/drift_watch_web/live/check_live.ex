defmodule DriftWatchWeb.CheckLive do
  @moduledoc """
  One check: its drift history and its latest runs.

  Runs are a LiveView stream, so a new run is pushed to the top of the list without sending
  the older ones again. The drift history is small and gets reloaded with every run.
  """

  use DriftWatchWeb, :live_view

  alias DriftWatch.Monitoring
  alias DriftWatch.Workers.CheckWorker

  @run_limit 25

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Monitoring.get_check(id) do
      nil ->
        {:ok, socket |> put_flash(:error, "This check does not exist.") |> push_navigate(to: ~p"/")}

      check ->
        if connected?(socket), do: Monitoring.subscribe()
        runs = Monitoring.list_runs(check.id, @run_limit)

        {:ok,
         socket
         |> assign(:page_title, "#{String.upcase(check.method)} #{check.path}")
         |> assign(:check, check)
         |> assign(:active_ids, active_ids(List.first(runs)))
         |> assign(:drifts, Monitoring.list_drifts(check.id))
         |> assign(:runs_empty?, runs == [])
         |> stream(:runs, runs, limit: @run_limit)}
    end
  end

  @impl true
  def handle_event("run_now", _params, socket) do
    {:ok, _job} = CheckWorker.enqueue(socket.assigns.check.id)
    {:noreply, put_flash(socket, :info, "Check queued. The run shows up below when it is done.")}
  end

  @impl true
  def handle_info({:run_recorded, check_id, run_id}, %{assigns: %{check: %{id: check_id}}} = socket) do
    run = Monitoring.get_run!(run_id)

    {:noreply,
     socket
     |> assign(:active_ids, active_ids(run))
     |> assign(:drifts, Monitoring.list_drifts(check_id))
     |> assign(:runs_empty?, false)
     |> stream_insert(:runs, run, at: 0, limit: @run_limit)}
  end

  def handle_info({:run_recorded, _other_check_id, _run_id}, socket), do: {:noreply, socket}

  # The drifts of the latest run are the active ones.
  defp active_ids(nil), do: MapSet.new()
  defp active_ids(run), do: MapSet.new(run.drifts, & &1.id)

  defp active?(drift, active_ids), do: MapSet.member?(active_ids, drift.id)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:dashboard}>
      <.link navigate={~p"/"} class="text-sm text-base-content/70 hover:underline">
        <.icon name="hero-arrow-left" class="size-4" /> Dashboard
      </.link>

      <div class="mt-3 mb-8 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 class="text-xl"><.endpoint check={@check} /></h1>
          <p class="mt-1 text-sm text-base-content/70">
            {@check.api.name} · every {@check.interval_minutes} min · times are UTC
          </p>
        </div>
        <button id="run-now" phx-click="run_now" class="btn btn-primary btn-sm">
          <.icon name="hero-play" class="size-4" /> Run now
        </button>
      </div>

      <section class="mb-10">
        <h2 class="mb-1 font-semibold">Drift history</h2>
        <p class="mb-3 text-sm text-base-content/70">
          Every distinct mismatch this check has seen. Active means the latest run still sees it.
        </p>

        <div
          :if={@drifts == []}
          id="no-drifts"
          class="rounded-box border border-dashed border-base-300 p-6 text-sm text-base-content/70"
        >
          No drift seen yet.
        </div>

        <div :if={@drifts != []} class="overflow-x-auto rounded-box border border-base-300">
          <table id="drifts" class="table table-sm">
            <thead>
              <tr>
                <th>Kind</th>
                <th>Path</th>
                <th>Spec says</th>
                <th>API sent</th>
                <th>First seen</th>
                <th>Last seen</th>
                <th class="text-right">Seen</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={drift <- @drifts}
                id={"drift-#{drift.id}"}
                class={[!active?(drift, @active_ids) && "opacity-60"]}
              >
                <td class="whitespace-nowrap">
                  <.drift_kind kind={drift.kind} />
                  <span :if={active?(drift, @active_ids)} class="badge badge-xs badge-neutral ml-1">active</span>
                </td>
                <td class="font-mono text-xs">{drift.path}</td>
                <td class="font-mono text-xs">{drift.expected}</td>
                <td class="font-mono text-xs">{drift.actual}</td>
                <td class="whitespace-nowrap text-xs">{format_time(drift.first_seen_at)}</td>
                <td class="whitespace-nowrap text-xs">{format_time(drift.last_seen_at)}</td>
                <td class="text-right tabular-nums">{drift.seen_count}×</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <h2 class="mb-3 font-semibold">Latest runs</h2>

        <div
          :if={@runs_empty?}
          id="no-runs"
          class="rounded-box border border-dashed border-base-300 p-6 text-sm text-base-content/70"
        >
          No runs yet. The scheduler picks this check up within a minute. Press Run now to run it right away.
        </div>

        <ul
          id="runs"
          phx-update="stream"
          class="divide-y divide-base-300 rounded-box border border-base-300 empty:hidden"
        >
          <li :for={{dom_id, run} <- @streams.runs} id={dom_id} class="px-4 py-3">
            <details>
              <summary class="flex cursor-pointer list-none flex-wrap items-center gap-3">
                <span class="w-36 whitespace-nowrap text-sm">{format_time(run.inserted_at)}</span>
                <.run_status run={run} />
                <span
                  :if={run.duration_ms}
                  class="w-16 font-mono text-xs tabular-nums text-base-content/60"
                >
                  {run.duration_ms} ms
                </span>
                <.run_drifts run={run} />
              </summary>

              <div class="mt-3 space-y-3">
                <p :if={run.error} class="text-sm text-error">{run.error}</p>

                <ul :if={run.drifts != []} class="space-y-1 text-sm">
                  <li :for={drift <- run.drifts} class="font-mono text-xs">
                    <span class="font-semibold">{drift.path}</span>: spec says {drift.expected}, API sent {drift.actual}
                  </li>
                </ul>

                <pre
                  :if={run.response_sample}
                  class="max-h-80 overflow-auto rounded-box bg-base-200 p-3 text-xs"
                >{run.response_sample}</pre>
              </div>
            </details>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
