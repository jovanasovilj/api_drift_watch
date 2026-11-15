defmodule DriftWatch.DataCase do
  @moduledoc """
  The test case for tests that use the database.

  Each test runs in the SQL sandbox, so its database changes are rolled back at the end
  and tests can run with `async: true`.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import DriftWatch.DataCase
      import Ecto
      import Ecto.Changeset
      import Ecto.Query

      alias DriftWatch.Repo
    end
  end

  setup tags do
    DriftWatch.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(DriftWatch.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end
end
