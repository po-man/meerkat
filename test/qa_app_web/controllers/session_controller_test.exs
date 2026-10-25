defmodule QaAppWeb.SessionControllerTest do
  use QaAppWeb.ConnCase

  alias QaApp.Accounts
  alias QaAppWeb.AdminAuth

  @secret_path AdminAuth.secret_path()
  @access_code "test-access-code"

  setup do
    previous = System.get_env("SUPER_ADMIN_ACCESS_CODE")

    System.put_env("SUPER_ADMIN_ACCESS_CODE", @access_code)

    on_exit(fn ->
      case previous do
        nil -> System.delete_env("SUPER_ADMIN_ACCESS_CODE")
        _ -> System.put_env("SUPER_ADMIN_ACCESS_CODE", previous)
      end
    end)

    :ok
  end

  describe "GET secret sign-in page" do
    test "shows the first-time setup form when no super admin exists", %{conn: conn} do
      refute Accounts.super_admin_exists?()

      conn = get(conn, @secret_path)

      html = html_response(conn, 200)
      assert html =~ "Super Admin Setup"
      assert html =~ "Access Code"
      assert html =~ ~s(action="#{@secret_path}")
    end

    test "shows only username and password when a super admin exists", %{conn: conn} do
      {:ok, _} = Accounts.create_super_admin(%{"username" => "root", "password" => "secret123"})

      conn = get(conn, @secret_path)

      html = html_response(conn, 200)
      assert html =~ "Admin Portal"
      assert html =~ "Username"
      assert html =~ "Password"
      refute html =~ "Access Code"
    end

    test "redirects an already signed-in room admin to the admin dashboard", %{conn: conn} do
      {:ok, _} = Accounts.create_super_admin(%{"username" => "root", "password" => "secret123"})
      {:ok, _} = Accounts.create_room_admin(%{"username" => "mod", "password" => "secret123"})

      conn = post(conn, @secret_path, %{"username" => "mod", "password" => "secret123"})
      assert redirected_to(conn) == "/admin/dashboard"

      conn = get(conn, @secret_path)
      assert redirected_to(conn) == "/admin/dashboard"
    end

    test "redirects an already signed-in super admin to the super admin dashboard", %{conn: conn} do
      {:ok, _} = Accounts.create_super_admin(%{"username" => "root", "password" => "secret123"})

      conn = post(conn, @secret_path, %{"username" => "root", "password" => "secret123"})
      assert redirected_to(conn) == "/super-admin"

      conn = get(conn, @secret_path)
      assert redirected_to(conn) == "/super-admin"
    end
  end

  describe "POST secret sign-in page (first-time setup)" do
    test "rejects an invalid access code and creates no user", %{conn: conn} do
      conn =
        post(conn, @secret_path, %{
          "access_code" => "wrong-code",
          "username" => "superadmin",
          "password" => "secret123"
        })

      assert html_response(conn, 200) =~ "Invalid access code"
      refute Accounts.super_admin_exists?()
    end

    test "creates the super admin and signs them in", %{conn: conn} do
      conn =
        post(conn, @secret_path, %{
          "access_code" => @access_code,
          "username" => "superadmin",
          "password" => "secret123"
        })

      assert redirected_to(conn) == "/super-admin"

      assert %{} = user = Accounts.get_user_by_username("superadmin")
      assert user.role == :super_admin
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
      refute Accounts.super_admin_exists?()
    end
  end

  describe "POST secret sign-in page (login)" do
    setup do
      {:ok, _} = Accounts.create_super_admin(%{"username" => "root", "password" => "secret123"})
      {:ok, _} = Accounts.create_room_admin(%{"username" => "mod", "password" => "secret123"})
      :ok
    end

    test "logs a super admin in and redirects to the super admin dashboard", %{conn: conn} do
      conn = post(conn, @secret_path, %{"username" => "root", "password" => "secret123"})
      assert redirected_to(conn) == "/super-admin"
    end

    test "logs a room admin in and redirects to the admin dashboard", %{conn: conn} do
      conn = post(conn, @secret_path, %{"username" => "mod", "password" => "secret123"})
      assert redirected_to(conn) == "/admin/dashboard"
    end

    test "rejects invalid credentials", %{conn: conn} do
      conn = post(conn, @secret_path, %{"username" => "root", "password" => "nope"})
      assert html_response(conn, 200) =~ "Invalid username or password"
    end
  end

  describe "removed public routes" do
    test "the old /login route no longer exists", %{conn: conn} do
      assert response(get(conn, "/login"), 404)
    end

    test "the old /super-admin/setup route no longer exists", %{conn: conn} do
      assert response(get(conn, "/super-admin/setup"), 404)
    end
  end
end
