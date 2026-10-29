defmodule QaAppWeb.SessionController do
  use QaAppWeb, :controller

  alias QaApp.Accounts
  alias QaAppWeb.AdminAuth

  # Renders the combined sign-in page.
  #
  # * Already signed in  -> redirect to the user's own dashboard
  # * No admin yet       -> first-time setup form (access code + credentials)
  # * Admin exists       -> plain username/password form
  def new(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        render(conn, :new,
          setup_mode: !Accounts.admin_exists?(),
          login_path: AdminAuth.secret_path(),
          form: Phoenix.Component.to_form(%{}),
          error_message: nil
        )

      user ->
        conn
        |> put_flash(:info, "You are already signed in as #{user.username}.")
        |> redirect(to: AdminAuth.dashboard_path(user))
    end
  end

  def create(conn, params) do
    if Accounts.admin_exists?() do
      authenticate(conn, params)
    else
      create_admin(conn, params)
    end
  end

  defp authenticate(conn, params) do
    username = param(params, "username")
    password = param(params, "password")

    case Accounts.authenticate_user(username || "", password || "") do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome back, #{user.username}!")
        |> QaAppWeb.UserAuth.log_in_user(user)
        |> redirect(to: AdminAuth.dashboard_path(user))

      {:error, :invalid_credentials} ->
        render_error(conn, false, "Invalid username or password")
    end
  end

  defp create_admin(conn, params) do
    access_code = param(params, "access_code")
    expected_code = System.get_env("ADMIN_ACCESS_CODE")

    if access_code && access_code == expected_code do
      attrs = %{
        "username" => param(params, "username"),
        "password" => param(params, "password")
      }

      case Accounts.create_admin(attrs) do
        {:ok, user} ->
          conn
          |> put_flash(:info, "Admin account created. Welcome, #{user.username}!")
          |> QaAppWeb.UserAuth.log_in_user(user)
          |> redirect(to: AdminAuth.dashboard_path(user))

        {:error, changeset} ->
          render_error(conn, true, "Validation error: #{format_errors(changeset)}")
      end
    else
      render_error(conn, true, "Invalid access code.")
    end
  end

  defp render_error(conn, setup_mode, error_message) do
    render(conn, :new,
      setup_mode: setup_mode,
      login_path: AdminAuth.secret_path(),
      form: Phoenix.Component.to_form(%{}),
      error_message: error_message
    )
  end

  # Accepts flat params as well as nested "user[...]" / "setup[...]" params.
  defp param(params, key) do
    params[key] || get_in(params, ["user", key]) || get_in(params, ["setup", key])
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        atom = String.to_existing_atom(key)
        value = if is_list(opts), do: Keyword.get(opts, atom, key), else: Map.get(opts, atom, key)
        to_string(value)
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k} #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> QaAppWeb.UserAuth.log_out_user()
  end
end
