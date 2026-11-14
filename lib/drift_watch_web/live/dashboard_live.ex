defmodule DriftWatchWeb.DashboardLive do
  @moduledoc """
  All watched APIs and their checks with the outcome of the latest run.

  The page reloads its data whenever a run is recorded. That is a handful of rows, so a
  full reload is simpler than patching single rows and still cheap.
  """

  use DriftWatchWeb, :live_view

  alias DriftWatch.Monitoring
  alias DriftWatch.Workers.CheckWorker

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Monitoring.subscribe()

    {:ok, socket |> assign(:page_title, "Dashboard") |> load()}
  end

  @impl true
  def handle_event("run_now", %{"id" => id}, socket) do
    {:ok, _job} = CheckWorker.enqueue(String.to_integer(id))
    {:noreply, put_flash(socket, :info, "Check queued. The result shows up here when it is done.")}
  end

  @impl true
  def handle_info({:run_recorded, _check_id, _run_id}, socket) do
    {:noreply, load(socket)}
  end

  defp load(socket), do: assign(socket, :apis, Monitoring.dashboard())

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mb-8">
        <h1 class="text-2xl font-semibold">Dashboard</h1>
        <p class="mt-1 text-base-content/70">
          Every check calls a real endpoint on a schedule and compares the response with the
          OpenAPI spec. Times are UTC.
        </p>
      </div>

      <div
        :if={@apis == []}
        id="empty-state"
        class="rounded-box border border-dashed border-base-300 p-10 text-center"
      >
        <p class="font-medium">No APIs are watched yet.</p>
        <p class="mt-1 text-sm text-base-content/70">
          Run <code class="font-mono">mix run priv/repo/seeds.exs</code> to add the drifty demo API.
        </p>
      </div>

      <section
        :for={%{api: api, checks: checks} <- @apis}
        id={"api-#{api.id}"}
        class="mb-8 overflow-hidden rounded-box border border-base-300 bg-base-100"
      >
        <header class="flex flex-wrap items-baseline justify-between gap-2 border-b border-base-300 bg-base-200/50 px-4 py-3">
          <div>
            <h2 class="font-semibold">{api.name}</h2>
            <p class="font-mono text-xs text-base-content/60">{api.base_url}</p>
          </div>
          <p class="text-xs text-base-content/60">
            <a href={api.spec_url} class="link link-hover" target="_blank" rel="noopener noreferrer">
              Spec
            </a>
            <%= if api.spec_fetched_at do %>
              loaded {format_time(api.spec_fetched_at)}
            <% else %>
              loads on the first run
            <% end %>
          </p>
        </header>

        <div class="overflow-x-auto">
          <%!-- Fixed column widths so the columns line up across every API section --%>
          <table class="table min-w-[56rem] table-fixed">
            <thead>
              <tr>
                <th>Endpoint</th>
                <th class="w-24">Status</th>
                <th class="w-56">Drift in last run</th>
                <th class="w-24 text-right">Time</th>
                <th class="w-44">Last run</th>
                <th class="w-28"><span class="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={%{check: check, latest_run: run} <- checks}
                id={"check-#{check.id}"}
                class="hover:bg-base-200/50"
              >
                <td>
                  <.link navigate={~p"/checks/#{check.id}"} class="hover:underline">
                    <.endpoint check={check} />
                  </.link>
                  <p class="text-xs text-base-content/50">
                    every {check.interval_minutes} min{if(!check.enabled, do: ", paused")}
                  </p>
                </td>
                <td><.run_status run={run} /></td>
                <td><.run_drifts run={run} /></td>
                <td class="text-right font-mono text-sm tabular-nums">
                  {if run && run.duration_ms, do: "#{run.duration_ms} ms"}
                </td>
                <td class="whitespace-nowrap text-sm">{format_time(run && run.inserted_at)}</td>
                <td class="text-right">
                  <button
                    id={"run-now-#{check.id}"}
                    phx-click="run_now"
                    phx-value-id={check.id}
                    class="btn btn-ghost btn-xs whitespace-nowrap"
                  >
                    <.icon name="hero-play" class="size-4" /> Run now
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
