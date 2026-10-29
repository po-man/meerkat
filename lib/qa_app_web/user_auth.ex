defmodule QaAppWeb.UserAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias QaApp.Accounts
  alias QaAppWeb.AdminAuth

  def log_in_user(conn, user) do
    conn
    |> put_session(:user_id, user.id)
    |> configure_session(renew: true)
  end

  def log_out_user(conn) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end

  def fetch_current_user(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        assign(conn, :current_user, nil)

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            # Stale session pointing at a deleted user: clear it instead of
            # raising on every request.
            conn
            |> configure_session(drop: true)
            |> assign(:current_user, nil)

          user ->
            assign(conn, :current_user, user)
        end
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: AdminAuth.secret_path())
      |> halt()
    end
  end

  def require_admin(conn, _opts) do
    user = conn.assigns[:current_user]

    cond do
      user && user.role == :admin ->
        conn

      user ->
        conn
        |> put_flash(:error, "Access denied. Admin privileges required.")
        |> redirect(to: AdminAuth.dashboard_path(user))
        |> halt()

      true ->
        conn
        |> put_flash(:error, "You must log in to access this page.")
        |> redirect(to: AdminAuth.secret_path())
        |> halt()
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, Phoenix.Component.assign(socket, :current_user, user_from_session(session))}
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    case user_from_session(session) do
      nil ->
        {:halt, Phoenix.LiveView.redirect(socket, to: AdminAuth.secret_path())}

      user ->
        {:cont, Phoenix.Component.assign(socket, :current_user, user)}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    case user_from_session(session) do
      nil ->
        {:halt, Phoenix.LiveView.redirect(socket, to: AdminAuth.secret_path())}

      %{role: :admin} = user ->
        {:cont, Phoenix.Component.assign(socket, :current_user, user)}

      user ->
        {:halt, Phoenix.LiveView.redirect(socket, to: AdminAuth.dashboard_path(user))}
    end
  end

  defp user_from_session(session) do
    case session["user_id"] do
      nil -> nil
      user_id -> Accounts.get_user(user_id)
    end
  end
end
