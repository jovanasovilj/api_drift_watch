defmodule DriftWatchWeb.DriftComponents do
  @moduledoc """
  Small pieces shared by the pages: endpoint labels, status badges, drift kind badges and
  time formatting.
  """

  use Phoenix.Component

  alias DriftWatch.Checker.Drift

  @kind_labels %{
    missing_field: "Missing field",
    wrong_type: "Wrong type",
    unexpected_null: "Unexpected null",
    extra_field: "Extra field",
    invalid_value: "Invalid value",
    undocumented_status: "Undocumented status"
  }

  @doc """
  Shows a check as its method, path template and params.
  """
  attr :check, :map, required: true

  def endpoint(assigns) do
    ~H"""
    <span class="font-mono text-sm [overflow-wrap:anywhere]">
      <span class="font-semibold uppercase text-primary">{@check.method}</span>
      {@check.path}
      <span :if={@check.params != %{}} class="text-base-content/50">
        {format_params(@check.params)}
      </span>
    </span>
    """
  end

  @doc """
  Shows the outcome of a run: the status code, the error or that it did not run yet.
  """
  attr :run, :map, default: nil

  def run_status(assigns) do
    ~H"""
    <span class={["badge badge-sm font-mono", status_class(@run)]} title={@run && @run.error}>
      {status_label(@run)}
    </span>
    """
  end

  @doc """
  Shows one drift kind as a badge.
  """
  attr :kind, :atom, required: true

  def drift_kind(assigns) do
    assigns = assign(assigns, :label, Map.fetch!(@kind_labels, assigns.kind))

    ~H"""
    <span class={["badge badge-sm whitespace-nowrap", kind_class(@kind)]}>{@label}</span>
    """
  end

  @doc """
  Shows the drifts of a run as one badge per kind with a count. A clean run says it matched.
  """
  attr :run, :map, default: nil

  def run_drifts(assigns) do
    assigns = assign(assigns, :counts, drift_counts(assigns.run))

    ~H"""
    <span :if={is_nil(@run)} class="text-base-content/40">Not run yet</span>
    <span :if={@run && @run.error} class="text-base-content/40">No response to compare</span>
    <span
      :if={@run && is_nil(@run.error) && @counts == []}
      class="whitespace-nowrap text-success text-sm"
    >
      Matches the spec
    </span>
    <span :if={@counts != []} class="flex flex-wrap gap-1">
      <span :for={{kind, count} <- @counts} class="inline-flex items-center gap-1">
        <.drift_kind kind={kind} />
        <span :if={count > 1} class="text-xs text-base-content/60">×{count}</span>
      </span>
    </span>
    """
  end

  @doc """
  Formats a UTC time for tables.
  """
  def format_time(nil), do: "never"
  def format_time(%DateTime{} = time), do: Calendar.strftime(time, "%b %-d, %H:%M:%S")

  defp format_params(params) do
    params
    |> Enum.sort()
    |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{value}" end)
  end

  defp drift_counts(%{error: nil, drifts: drifts}) when is_list(drifts) do
    drifts
    |> Enum.frequencies_by(& &1.kind)
    |> Enum.sort_by(fn {kind, _count} -> Enum.find_index(Drift.kinds(), &(&1 == kind)) end)
  end

  defp drift_counts(_run), do: []

  defp status_label(nil), do: "waiting"
  defp status_label(%{error: error}) when is_binary(error), do: "error"
  defp status_label(%{status: status}), do: Integer.to_string(status)

  defp status_class(nil), do: "badge-ghost"
  defp status_class(%{error: error}) when is_binary(error), do: "badge-error"
  defp status_class(%{status: status}) when status in 200..399, do: "badge-success badge-soft"
  defp status_class(%{status: status}) when status in 400..499, do: "badge-warning badge-soft"
  defp status_class(_run), do: "badge-error badge-soft"

  defp kind_class(:missing_field), do: "badge-error badge-soft"
  defp kind_class(:wrong_type), do: "badge-error badge-soft"
  defp kind_class(:unexpected_null), do: "badge-warning badge-soft"
  defp kind_class(:invalid_value), do: "badge-warning badge-soft"
  defp kind_class(:extra_field), do: "badge-info badge-soft"
  defp kind_class(:undocumented_status), do: "badge-secondary badge-soft"
end
