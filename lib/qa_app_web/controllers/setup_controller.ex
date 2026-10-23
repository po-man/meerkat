defmodule QaAppWeb.SetupController do
  use QaAppWeb, :controller
  alias QaApp.Accounts

  def new(conn, _params) do
    if Accounts.super_admin_exists?() do
      conn
      |> put_flash(:error, "Super Admin setup has already been completed.")
      |> redirect(to: "/login")
    else
      render(conn, :new, error_message: nil)
    end
  end

  def create(conn, params) do
    access_code = params["access_code"] || get_in(params, ["setup", "access_code"])
    username = params["username"] || get_in(params, ["setup", "username"])
    password = params["password"] || get_in(params, ["setup", "password"])

    expected_code = System.get_env("SUPER_ADMIN_ACCESS_CODE") || "secret123"

    cond do
      Accounts.super_admin_exists?() ->
        conn
        |> put_flash(:error, "Super Admin setup has already been completed.")
        |> redirect(to: "/login")

      access_code != expected_code ->
        render(conn, :new, error_message: "Invalid Super Admin Access Code")

      true ->
        case Accounts.create_super_admin(%{"username" => username, "password" => password}) do
          {:ok, _user} ->
            conn
            |> put_flash(:info, "Super Admin account created successfully! Please log in.")
            |> redirect(to: "/login")

          {:error, changeset} ->
            errors =
              Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
                Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
                  to_string(Map.get(opts, String.to_existing_atom(key), key))
                end)
              end)
              |> Enum.map(fn {k, v} -> "#{k} #{Enum.join(v, ", ")}" end)
              |> Enum.join("; ")

            render(conn, :new, error_message: "Validation error: #{errors}")
        end
    end
  end
end
