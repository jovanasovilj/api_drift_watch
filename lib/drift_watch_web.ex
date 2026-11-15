defmodule DriftWatchWeb do
  @moduledoc """
  The shared setup for the web layer: `use DriftWatchWeb, :live_view`, `:html`,
  `:controller` and so on pull in the imports and aliases each kind of module needs.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Phoenix.Controller
      import Phoenix.LiveView.Router
      import Plug.Conn
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]
      use Gettext, backend: DriftWatchWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      use Gettext, backend: DriftWatchWeb.Gettext

      import DriftWatchWeb.CoreComponents
      import DriftWatchWeb.DriftComponents
      import Phoenix.HTML

      alias DriftWatchWeb.Layouts
      alias Phoenix.LiveView.JS

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: DriftWatchWeb.Endpoint,
        router: DriftWatchWeb.Router,
        statics: DriftWatchWeb.static_paths()
    end
  end

  @doc """
  Pulls in the setup for `use DriftWatchWeb, :live_view` and the other kinds.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
