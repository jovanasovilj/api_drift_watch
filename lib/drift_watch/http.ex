defmodule DriftWatch.HTTP do
  @moduledoc """
  The one place where we build Req requests.

  Retries are off on purpose: a check should show what the API did on the first try, so a
  flaky endpoint shows up as drift instead of being hidden by a retry.

  Tests swap the network for `Req.Test` through the `:req_options` config.
  """

  @defaults [retry: false, receive_timeout: 10_000, user_agent: "api-drift-watch"]

  @doc """
  Returns a `Req.Request` with our defaults, the configured options and `options` on top.
  """
  def new(options \\ []) do
    configured = Application.get_env(:drift_watch, :req_options, [])

    @defaults
    |> Keyword.merge(configured)
    |> Keyword.merge(options)
    |> Req.new()
  end
end
