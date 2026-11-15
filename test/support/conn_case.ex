defmodule DriftWatchWeb.ConnCase do
  @moduledoc """
  The test case for tests that need a connection, like controller and LiveView tests.

  Each test runs in the SQL sandbox, so its database changes are rolled back at the end
  and tests can run with `async: true`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use DriftWatchWeb, :verified_routes

      import DriftWatchWeb.ConnCase
      import Phoenix.ConnTest
      import Plug.Conn

      @endpoint DriftWatchWeb.Endpoint
    end
  end

  setup tags do
    DriftWatch.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
