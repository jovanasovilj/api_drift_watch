defmodule DriftWatchWeb.Gettext do
  @moduledoc """
  The Gettext backend. The core components use it to translate form errors.
  """
  use Gettext.Backend, otp_app: :drift_watch
end
