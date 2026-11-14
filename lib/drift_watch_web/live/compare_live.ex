defmodule DriftWatchWeb.CompareLive do
  @moduledoc """
  Compares a pasted response with a pasted spec, without watching anything.

  The page has two forms. The spec form parses the spec as it changes and fills the list of
  operations. The response form compares a status and a body with the chosen operation.

  Both text areas use `phx-update="ignore"`, so the server never sends a pasted spec back to
  the browser. To fill them with the example the page navigates, which mounts it fresh.
  """

  use DriftWatchWeb, :live_view

  alias DriftWatch.Comparison
  alias DriftWatch.Drifty

  @example_operation "get /drifty/stations/{id}"

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Compare", spec: nil, operations: [], spec_error: nil, result: nil)
      |> assign(spec_text: "", body_text: "", operation: nil, status: "200")

    {:ok, maybe_load_example(socket, params)}
  end

  @impl true
  def handle_event("load_spec", %{"spec" => text}, socket) do
    {:noreply, load_spec(socket, text)}
  end

  def handle_event("compare", params, %{assigns: %{spec: nil}} = socket) do
    {:noreply, assign(socket, operation: params["operation"], status: params["status"])}
  end

  def handle_event("compare", params, socket) do
    result = Comparison.compare(socket.assigns.spec, Map.take(params, ["operation", "status", "body"]))
    {:noreply, assign(socket, result: result, operation: params["operation"], status: params["status"])}
  end

  defp maybe_load_example(socket, %{"example" => "drifty"}) do
    params = %{"operation" => @example_operation, "status" => "200", "body" => example_body()}
    socket = socket |> assign(spec_text: Drifty.spec_json(), body_text: params["body"]) |> load_spec(Drifty.spec_json())

    assign(socket,
      operation: @example_operation,
      result: Comparison.compare(socket.assigns.spec, params)
    )
  end

  defp maybe_load_example(socket, _params), do: socket

  # A drifty station with five drifts at once: a missing name, a temperature as text, a
  # null latitude, an unknown status and a field the spec never mentions.
  defp example_body do
    {200, station} = Drifty.station("1", "none")

    station
    |> Map.delete("name")
    |> Map.update!("temperature_c", &to_string/1)
    |> put_in(["location", "lat"], nil)
    |> Map.put("status", "maintenance")
    |> Map.put("humidity_pct", 81)
    |> Jason.encode!(pretty: true)
  end

  defp load_spec(socket, text) do
    if String.trim(text) == "" do
      assign(socket, spec: nil, operations: [], spec_error: nil, result: nil)
    else
      case Comparison.load_spec(text) do
        {:ok, %{spec: spec, operations: operations}} ->
          options = Enum.map(operations, &operation_option/1)
          assign(socket, spec: spec, operations: options, spec_error: nil, result: nil)

        {:error, reason} ->
          assign(socket, spec: nil, operations: [], spec_error: Comparison.describe_error(reason), result: nil)
      end
    end
  end

  defp count([_one], noun), do: "1 #{noun}"
  defp count(items, noun), do: "#{length(items)} #{noun}s"

  defp operation_option({method, path}), do: {"#{String.upcase(method)} #{path}", "#{method} #{path}"}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mb-8 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold">Compare a response with its spec</h1>
          <p class="mt-1 max-w-2xl text-base-content/70">
            Paste an OpenAPI 3.1 spec and a response body. The server compares them the same way it checks the watched APIs. Nothing is fetched and nothing is stored.
          </p>
        </div>
        <div class="flex gap-2">
          <.link id="load-example" navigate={~p"/compare?example=drifty"} class="btn btn-sm">
            Try the example
          </.link>
          <.link navigate={~p"/compare"} class="btn btn-ghost btn-sm">Clear</.link>
        </div>
      </div>

      <div class="grid gap-8 lg:grid-cols-2">
        <.form for={%{}} id="spec-form" phx-change="load_spec" phx-submit="load_spec">
          <.input
            type="textarea"
            id="spec"
            name="spec"
            label="Spec as JSON or YAML"
            value={@spec_text}
            phx-update="ignore"
            phx-debounce="400"
            rows="18"
            spellcheck="false"
            placeholder="openapi: 3.1.0"
            class="w-full textarea font-mono text-xs"
          />
          <p :if={@spec_error} id="spec-error" class="text-sm text-error">{@spec_error}</p>
          <p :if={@spec} id="spec-summary" class="text-sm text-base-content/70">
            OpenAPI {@spec["openapi"]} · {count(@operations, "operation")}
          </p>
        </.form>

        <div>
          <.form for={%{}} id="response-form" phx-submit="compare">
            <.input
              type="select"
              id="operation"
              name="operation"
              label="Operation"
              value={@operation}
              options={@operations}
              prompt={if @spec, do: "Pick an operation", else: "Paste a spec first"}
              disabled={is_nil(@spec)}
            />
            <.input
              type="number"
              id="status"
              name="status"
              label="Status code"
              value={@status}
              min="100"
              max="599"
            />
            <.input
              type="textarea"
              id="body"
              name="body"
              label="Response body as JSON"
              value={@body_text}
              phx-update="ignore"
              rows="10"
              spellcheck="false"
              class="w-full textarea font-mono text-xs"
            />
            <button type="submit" class="btn btn-primary btn-sm" disabled={is_nil(@spec)}>
              Compare
            </button>
          </.form>
        </div>
      </div>

      <section id="result" class="mt-8">
        <.compare_result result={@result} />
      </section>
    </Layouts.app>
    """
  end

  attr :result, :any, required: true

  defp compare_result(%{result: nil} = assigns), do: ~H""

  defp compare_result(%{result: {:error, reason}} = assigns) do
    assigns = assign(assigns, :message, Comparison.describe_error(reason))

    ~H"""
    <p id="compare-error" class="text-sm text-error">{@message}</p>
    """
  end

  defp compare_result(%{result: {:ok, []}} = assigns) do
    ~H"""
    <p id="no-drift" class="text-success">The response matches the spec.</p>
    """
  end

  defp compare_result(%{result: {:ok, drifts}} = assigns) do
    assigns = assign(assigns, :drifts, drifts)

    ~H"""
    <h2 class="mb-3 font-semibold">{count(@drifts, "drift")}</h2>
    <div class="overflow-x-auto rounded-box border border-base-300">
      <table id="drifts" class="table table-sm">
        <thead>
          <tr>
            <th>Kind</th>
            <th>Path</th>
            <th>Spec says</th>
            <th>Response has</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={drift <- @drifts}>
            <td class="whitespace-nowrap"><.drift_kind kind={drift.kind} /></td>
            <td class="font-mono text-xs">{drift.path}</td>
            <td class="font-mono text-xs">{drift.expected}</td>
            <td class="font-mono text-xs">{drift.actual}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
