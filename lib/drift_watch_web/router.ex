defmodule DriftWatchWeb.Router do
  use DriftWatchWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DriftWatchWeb.Layouts, :root}
    plug :protect_from_forgery
    # Everything comes from this app and nothing runs inline. That is why the theme script in
    # the root layout is a file of its own.
    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'"
    }
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DriftWatchWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/drifty", DriftWatchWeb do
    pipe_through :api

    get "/openapi.json", DriftyController, :spec
    get "/stations/:id", DriftyController, :station
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:drift_watch, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DriftWatchWeb.Telemetry
    end
  end
end
