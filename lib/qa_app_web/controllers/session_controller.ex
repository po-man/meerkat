defmodule QaAppWeb.SessionController do
  use QaAppWeb, :controller
  alias QaApp.Accounts

  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  def create(conn, params) do
    username = params["username"] || get_in(params, ["user", "username"])
    password = params["password"] || get_in(params, ["user", "password"])

    case Accounts.authenticate_user(username || "", password || "") do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome back, #{user.username}!")
        |> QaAppWeb.UserAuth.log_in_user(user)
        |> redirect(
          to: if(user.role == :super_admin, do: "/super-admin", else: "/admin/dashboard")
        )

      {:error, :invalid_credentials} ->
        render(conn, :new, error_message: "Invalid username or password")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> QaAppWeb.UserAuth.log_out_user()
  end
end
