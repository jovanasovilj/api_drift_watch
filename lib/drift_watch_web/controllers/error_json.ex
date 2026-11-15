defmodule DriftWatchWeb.ErrorJSON do
  @moduledoc """
  Renders errors on JSON requests as `{"errors": {"detail": "Not Found"}}`.
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
