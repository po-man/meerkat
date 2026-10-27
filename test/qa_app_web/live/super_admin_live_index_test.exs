defmodule QaAppWeb.SuperAdminLiveIndexTest do
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

  defp open_super_admin(conn) do
    conn = login_as(conn, "root")
    {:ok, view, _html} = live(conn, "/super-admin")
    view
  end

  describe "creating a room with an expiry" do
    setup %{conn: conn} do
      view = open_super_admin(conn)
      view |> element(~s(button[phx-click="open_create_room"])) |> render_click()
      {:ok, view: view}
    end

    test "offers the allowed expiry durations, defaulting to 7 days", %{view: view} do
      assert has_element?(view, ~s(#create-room-form select[name="room[expires_in]"]))
      assert render(view) =~ ~s(value="3 minutes")
      assert render(view) =~ ~s(value="30 minutes")
      assert render(view) =~ ~s(value="7 days")
      assert render(view) =~ ~s(<option selected="" value="7 days">7 days</option>)
    end

    test "creates a room whose expiry is derived from the chosen duration", %{view: view} do
      view
      |> form("#create-room-form",
        room: %{
          "slug" => "expiry-room",
          "title" => "Expiry Room",
          "admin_id" => "",
          "char_limit" => "320",
          "expires_in" => "7 days"
        }
      )
      |> render_submit()

      assert render(view) =~ "Room created successfully."

      room = Events.get_room_by_slug("expiry-room")
      assert room
      assert room.expires_at

      expected = DateTime.add(DateTime.utc_now(), 7 * 24 * 60 * 60, :second)
      assert DateTime.diff(room.expires_at, expected) |> abs() < 5
    end

    test "rejects an expiry that is not one of the allowed options", %{view: view} do
      html =
        render_submit(view, "create_room", %{
          "room" => %{
            "slug" => "invalid-expiry-room",
            "title" => "Invalid Expiry Room",
            "admin_id" => "",
            "char_limit" => "320",
            "expires_in" => "2 weeks"
          }
        })

      assert html =~ "is not a valid option"
      assert is_nil(Events.get_room_by_slug("invalid-expiry-room"))
    end
  end

  describe "configure room modal" do
    setup do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "config-no-expiry",
          "title" => "Config Room",
          "char_limit" => 320,
          "is_active" => true
        })

      {:ok, room: room}
    end

    test "shows the expiry in the rooms table but does not expose it as editable", %{
      conn: conn,
      room: room
    } do
      view = open_super_admin(conn)

      assert render(view) =~ "Expires"
      assert render(view) =~ Calendar.strftime(room.expires_at, "%b %d, %Y")

      view |> element(~s(button[phx-click="open_configure_room"])) |> render_click()

      assert has_element?(view, "#configure-room-form")
      refute has_element?(view, ~s(#configure-room-form [name="room[expires_in]"]))
      refute has_element?(view, ~s(#configure-room-form [name="room[expires_at]"]))
    end
  end

  describe "room expiry cleanup" do
    test "removes an expired room from the rooms table without a reload", %{conn: conn} do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "expires-soon",
          "title" => "Expires Soon",
          "char_limit" => 320,
          "is_active" => true,
          "expires_in" => "3 minutes"
        })

      view = open_super_admin(conn)

      assert render(view) =~ "Expires Soon"

      # Simulate the scheduler: move the expiry into the past and clean up.
      room
      |> Ecto.Changeset.change(
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)
      )
      |> QaApp.Repo.update!()

      assert Events.cleanup_expired_rooms() != []

      render(view)
      refute render(view) =~ "Expires Soon"
    end
  end
end
