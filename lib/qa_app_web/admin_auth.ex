defmodule QaAppWeb.AdminAuth do
  @moduledoc """
  Centralized paths for the admin sign-in flow.

  The sign-in / first-time-setup page is deliberately **not** linked from any
  public page: its URL is only known to the admins (secret by convention).
  To use a different URL, update `@secret_path` below.
  """

  @secret_path "/login"

  @doc """
  The secret URL of the combined sign-in / first-time setup page.
  """
  def secret_path, do: @secret_path

  @doc """
  The dashboard a signed-in user should be sent to, based on their role:

    * `:admin`     -> `/admin`
    * `:moderator` -> `/moderator/dashboard`

  """
  def dashboard_path(%{role: :admin}), do: "/admin"
  def dashboard_path(_user), do: "/moderator/dashboard"
end
