defmodule DriftWatch do
  @moduledoc """
  API Drift Watch calls API endpoints on a schedule and compares each response with the
  OpenAPI spec of that API.

  `DriftWatch.Monitoring` holds the watched APIs, checks, runs and drift history.
  `DriftWatch.Checker` does the comparing and `DriftWatch.Comparison` runs it on a pasted
  spec and response.
  """
end
