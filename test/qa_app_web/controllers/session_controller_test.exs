defmodule QaAppWeb.SessionControllerTest do
  use QaAppWeb.ConnCase

  alias QaApp.Accounts
  alias QaAppWeb.AdminAuth

  @secret_path AdminAuth.secret_path()
  @access_code "test-access-code"

  setup do
    previous = System.get_env("ADMIN_ACCESS_CODE")

    System.put_env("ADMIN_ACCESS_CODE", @access_code)

    on_exit(fn ->
      case previous do
        nil -> System.delete_env("ADMIN_ACCESS_CODE")
        _ -> System.put_env("ADMIN_ACCESS_CODE", previous)
      end
    end)

    :ok
  end

  describe "GET secret sign-in page" do
    test "shows the first-time setup form when no admin exists", %{conn: conn} do
      refute Accounts.admin_exists?()

      conn = get(conn, @secret_path)

      html = html_response(conn, 200)
      assert html =~ "Admin Setup"
      assert html =~ "Access Code"
      assert html =~ ~s(action="#{@secret_path}")
    end

    test "shows only username and password when an admin exists", %{conn: conn} do
      {:ok, _} = Accounts.create_admin(%{"username" => "root", "password" => "secret123"})

      conn = get(conn, @secret_path)

      html = html_response(conn, 200)
      assert html =~ "Admin Portal"
      assert html =~ "Username"
      assert html =~ "Password"
      refute html =~ "Access Code"
    end

    test "redirects an already signed-in moderator to the moderator dashboard", %{conn: conn} do
      {:ok, _} = Accounts.create_admin(%{"username" => "root", "password" => "secret123"})
      {:ok, _} = Accounts.create_moderator(%{"username" => "mod", "password" => "secret123"})

      conn = post(conn, @secret_path, %{"username" => "mod", "password" => "secret123"})
      assert redirected_to(conn) == "/moderator/dashboard"

      conn = get(conn, @secret_path)
      assert redirected_to(conn) == "/moderator/dashboard"
    end

    test "redirects an already signed-in admin to the admin dashboard", %{conn: conn} do
      {:ok, _} = Accounts.create_admin(%{"username" => "root", "password" => "secret123"})

      conn = post(conn, @secret_path, %{"username" => "root", "password" => "secret123"})
      assert redirected_to(conn) == "/admin"

      conn = get(conn, @secret_path)
      assert redirected_to(conn) == "/admin"
    end
  end

  describe "POST secret sign-in page (first-time setup)" do
    test "rejects an invalid access code and creates no user", %{conn: conn} do
      conn =
        post(conn, @secret_path, %{
          "access_code" => "wrong-code",
          "username" => "admin",
          "password" => "secret123"
        })

      assert html_response(conn, 200) =~ "Invalid access code"
      refute Accounts.admin_exists?()
    end

    test "rejects the former default access code when ADMIN_ACCESS_CODE is unset", %{conn: conn} do
      # There must be no built-in fallback: when the access code is not
      # configured, the old "secret123" default has to be rejected too.
      previous = System.get_env("ADMIN_ACCESS_CODE")
      System.delete_env("ADMIN_ACCESS_CODE")

      on_exit(fn ->
        case previous do
          nil -> :ok
          _ -> System.put_env("ADMIN_ACCESS_CODE", previous)
        end
      end)

      conn =
        post(conn, @secret_path, %{
          "access_code" => "secret123",
          "username" => "admin",
          "password" => "secret123"
        })

      assert html_response(conn, 200) =~ "Invalid access code"
      refute Accounts.admin_exists?()
    end

    test "creates the admin and signs them in", %{conn: conn} do
      conn =
        post(conn, @secret_path, %{
          "access_code" => @access_code,
          "username" => "admin",
          "password" => "secret123"
        })

      assert redirected_to(conn) == "/admin"

      assert %{} = user = Accounts.get_user_by_username("admin")
      assert user.role == :admin
      assert get_session(conn, :user_id) == user.id
    end

    test "shows validation errors for invalid setup credentials", %{conn: conn} do
      conn =
        post(conn, @secret_path, %{
          "access_code" => @access_code,
          "username" => "ab",
          "password" => "123"
        })

      assert html_response(conn, 200) =~ "Validation error"
      refute Accounts.admin_exists?()
    end
  end

  describe "POST secret sign-in page (login)" do
    setup do
      {:ok, _} = Accounts.create_admin(%{"username" => "root", "password" => "secret123"})
      {:ok, _} = Accounts.create_moderator(%{"username" => "mod", "password" => "secret123"})
      :ok
    end

    test "logs an admin in and redirects to the admin dashboard", %{conn: conn} do
      conn = post(conn, @secret_path, %{"username" => "root", "password" => "secret123"})
      assert redirected_to(conn) == "/admin"
    end

    test "logs a moderator in and redirects to the moderator dashboard", %{conn: conn} do
      conn = post(conn, @secret_path, %{"username" => "mod", "password" => "secret123"})
      assert redirected_to(conn) == "/moderator/dashboard"
    end

    test "rejects invalid credentials", %{conn: conn} do
      conn = post(conn, @secret_path, %{"username" => "root", "password" => "nope"})
      assert html_response(conn, 200) =~ "Invalid username or password"
    end
  end

  describe "DELETE /logout" do
    setup do
      {:ok, _} = Accounts.create_admin(%{"username" => "root", "password" => "secret123"})
      {:ok, _} = Accounts.create_moderator(%{"username" => "mod", "password" => "secret123"})
      :ok
    end

    test "clears the signed-in state of a moderator", %{conn: conn} do
      conn = post(conn, @secret_path, %{"username" => "mod", "password" => "secret123"})
      assert redirected_to(conn) == "/moderator/dashboard"

      conn = delete(conn, "/logout")
      assert redirected_to(conn) == "/"

      # the session is gone: protected pages redirect to the sign-in page again
      assert redirected_to(get(conn, "/moderator/dashboard")) == @secret_path
    end

    test "clears the signed-in state of an admin", %{conn: conn} do
      conn = post(conn, @secret_path, %{"username" => "root", "password" => "secret123"})
      assert redirected_to(conn) == "/admin"

      conn = delete(conn, "/logout")
      assert redirected_to(conn) == "/"

      assert redirected_to(get(conn, "/admin")) == @secret_path
    end
  end

  describe "removed public routes" do
    test "the old /super-admin/setup route no longer exists", %{conn: conn} do
      assert response(get(conn, "/super-admin/setup"), 404)
    end
  end
end
