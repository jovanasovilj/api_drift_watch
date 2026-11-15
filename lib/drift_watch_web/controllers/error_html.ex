defmodule DriftWatchWeb.ErrorHTML do
  @moduledoc """
  Renders errors on HTML requests as a plain status message, like "Not Found".
  """
  use DriftWatchWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
