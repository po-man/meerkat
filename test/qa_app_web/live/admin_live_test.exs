defmodule QaAppWeb.AdminLiveTest do
  use QaAppWeb.ConnCase

  alias QaApp.Accounts
  alias QaApp.Events
  alias QaAppWeb.AdminAuth

  @secret_path AdminAuth.secret_path()

  setup do
    {:ok, _} = Accounts.create_super_admin(%{"username" => "root", "password" => "secret123"})
    {:ok, _} = Accounts.create_room_admin(%{"username" => "mod", "password" => "secret123"})
    :ok
  end

  defp login_as(conn, username) do
    post(conn, @secret_path, %{"username" => username, "password" => "secret123"})
  end

  describe "header sign-out on protected pages" do
    test "is shown on the room admin dashboard", %{conn: conn} do
      conn = login_as(conn, "mod")

      html = html_response(get(conn, "/admin/dashboard"), 200)
      assert html =~ ~s(id="sign-out")
      assert html =~ "Sign Out"
      assert html =~ "mod"
    end

    test "is shown on the room moderator page", %{conn: conn} do
      {:ok, owner} = Accounts.create_room_admin(%{"username" => "owner", "password" => "secret123"})

      {:ok, room} =
        Events.create_room(%{
          "slug" => "townhall",
          "title" => "Town Hall",
          "word_limit" => 50,
          "is_active" => true,
          "admin_id" => owner.id
        })

      conn = login_as(conn, "owner")

      html = html_response(get(conn, "/admin/r/#{room.slug}"), 200)
      assert html =~ ~s(id="sign-out")
      assert html =~ "Sign Out"
    end

    test "is shown on the super admin dashboard", %{conn: conn} do
      conn = login_as(conn, "root")

      html = html_response(get(conn, "/super-admin"), 200)
      assert html =~ ~s(id="sign-out")
      assert html =~ "Sign Out"
    end

    test "is not shown to anonymous visitors (they are redirected to sign in)", %{conn: conn} do
      conn = get(conn, "/admin/dashboard")
      assert redirected_to(conn) == AdminAuth.secret_path()

      conn = get(conn, "/super-admin")
      assert redirected_to(conn) == AdminAuth.secret_path()
    end
  end
end
