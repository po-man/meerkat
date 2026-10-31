defmodule QaAppWeb.HealthController do
  @moduledoc """
  Liveness/readiness probe used by the container health check, the tunnel and
  uptime monitors.

  Deliberately outside every authenticated pipeline and excluded from
  `force_ssl`, so it can be called over plain HTTP from inside the container.
  """
  use QaAppWeb, :controller

  @db_timeout 5_000

  def show(conn, _params) do
    case check_database() do
      :ok -> send_resp(conn, 200, "ok")
      {:error, _reason} -> send_resp(conn, 503, "unavailable")
    end
  end

  defp check_database do
    {:ok, _result} = QaApp.Repo.query("SELECT 1", [], timeout: @db_timeout)
    :ok
  rescue
    # The repo may not be started yet (or the pool may be exhausted); a probe
    # should report unavailability, never crash with a 500 page.
    error -> {:error, error}
  catch
    # A dead pool process exits rather than raising.
    :exit, reason -> {:error, reason}
  end
end
