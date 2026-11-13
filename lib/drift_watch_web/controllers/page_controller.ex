defmodule DriftWatchWeb.PageController do
  use DriftWatchWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
