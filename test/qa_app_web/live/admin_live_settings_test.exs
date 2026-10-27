defmodule QaAppWeb.AdminLiveSettingsTest do
  use QaAppWeb.ConnCase

  import Phoenix.LiveViewTest

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

  describe "room settings page" do
    setup do
      {:ok, owner} =
        Accounts.create_room_admin(%{"username" => "settings-owner", "password" => "secret123"})

      {:ok, room} =
        Events.create_room(%{
          "slug" => "settings-room",
          "title" => "Settings Room",
          "intro_text" => "Original intro",
          "word_limit" => 50,
          "is_active" => true,
          "admin_id" => owner.id
        })

      {:ok, owner: owner, room: room}
    end

    test "renders the settings form with the current values and nav tabs", %{
      conn: conn,
      owner: owner,
      room: room
    } do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/admin/r/#{room.slug}/settings")

      assert has_element?(view, "#settings-form")
      assert has_element?(view, "#room-tabs")
      assert has_element?(view, "#room-tab-settings")
      assert has_element?(view, "#room-tab-questions")
      assert has_element?(view, ~s(a[href="/admin/r/#{room.slug}/export.csv"]))
      assert render(view) =~ ~s(id="sign-out")
    end

    test "updates the room settings on submit", %{conn: conn, owner: owner, room: room} do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/admin/r/#{room.slug}/settings")

      view
      |> form("#settings-form",
        room: %{
          "title" => "New Title",
          "intro_text" => "New intro",
          "word_limit" => "75"
        }
      )
      |> render_submit()

      assert render(view) =~ "Room settings updated successfully."

      updated_room = Events.get_room!(room.id)
      assert updated_room.title == "New Title"
      assert updated_room.intro_text == "New intro"
      assert updated_room.word_limit == 75
    end

    test "shows validation errors for an invalid word limit", %{
      conn: conn,
      owner: owner,
      room: room
    } do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/admin/r/#{room.slug}/settings")

      html =
        view
        |> form("#settings-form", room: %{"title" => "Valid Title", "word_limit" => "0"})
        |> render_submit()

      assert html =~ "must be greater than 0"
    end

    test "redirects an admin who does not own the room", %{conn: conn, room: room} do
      {:ok, other} =
        Accounts.create_room_admin(%{"username" => "other-admin", "password" => "secret123"})

      conn = login_as(conn, other.username)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/r/#{room.slug}/settings")
    end

    test "redirects anonymous visitors to sign in", %{conn: conn, room: room} do
      conn = get(conn, "/admin/r/#{room.slug}/settings")
      assert redirected_to(conn) == AdminAuth.secret_path()
    end
  end
end
