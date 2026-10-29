defmodule QaAppWeb.AdminLiveIndexTest do
  use QaAppWeb.ConnCase

  import Phoenix.LiveViewTest

  alias QaApp.Accounts
  alias QaApp.Events
  alias QaAppWeb.AdminAuth

  @secret_path AdminAuth.secret_path()

  setup do
    {:ok, _} = Accounts.create_admin(%{"username" => "root", "password" => "secret123"})
    {:ok, _} = Accounts.create_moderator(%{"username" => "mod", "password" => "secret123"})
    :ok
  end

  defp login_as(conn, username) do
    post(conn, @secret_path, %{"username" => username, "password" => "secret123"})
  end

  defp open_admin(conn) do
    conn = login_as(conn, "root")
    {:ok, view, _html} = live(conn, "/admin")
    view
  end

  describe "creating a room with an expiry" do
    setup %{conn: conn} do
      view = open_admin(conn)
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
          "moderator_id" => "",
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
            "moderator_id" => "",
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
      view = open_admin(conn)

      assert render(view) =~ "Expires"
      assert render(view) =~ Calendar.strftime(room.expires_at, "%b %d, %Y")
      assert render(view) =~ ~s(data-format="datetime")
      assert render(view) =~ ~s(phx-hook="LocalDateTime")

      view |> element(~s(button[phx-click="open_configure_room"])) |> render_click()

      assert has_element?(view, "#configure-room-form")
      refute has_element?(view, ~s(#configure-room-form [name="room[expires_in]"]))
      refute has_element?(view, ~s(#configure-room-form [name="room[expires_at]"]))
    end
  end

  describe "max visitors" do
    test "create room modal includes a max visitors field with unlimited support", %{conn: conn} do
      view = open_admin(conn)
      view |> element(~s(button[phx-click="open_create_room"])) |> render_click()

      assert has_element?(view, ~s(#create-room-form [name="room[max_visitors]"]))
    end

    test "configure room modal allows editing the max visitors", %{conn: conn} do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "config-max",
          "title" => "Config Max",
          "char_limit" => 320,
          "is_active" => true
        })

      view = open_admin(conn)
      view |> element(~s(button[phx-click="open_configure_room"])) |> render_click()

      assert has_element?(view, ~s(#configure-room-form [name="room[max_visitors]"]))
      assert is_nil(room.max_visitors) || room.max_visitors == 250
    end

    test "updating a room's max visitors persists the new limit", %{conn: conn} do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "update-max",
          "title" => "Update Max",
          "char_limit" => 320,
          "is_active" => true
        })

      view = open_admin(conn)
      view |> element(~s(button[phx-click="open_configure_room"])) |> render_click()

      view
      |> form("#configure-room-form",
        room: %{
          "title" => "Update Max",
          "slug" => "update-max",
          "char_limit" => "320",
          "max_visitors" => "75"
        }
      )
      |> render_submit()

      assert render(view) =~ "Room configured successfully."
      assert Events.get_room!(room.id).max_visitors == 75
    end
  end

  describe "live visitor counts" do
    test "shows the total live visitors and per-room counts", %{conn: conn} do
      {:ok, audience_room} =
        Events.create_room(%{
          "slug" => "living-room",
          "title" => "Living Room",
          "char_limit" => 320,
          "is_active" => true
        })

      # A real audience visitor connects first so the admin page has data.
      {:ok, _audience_view, _html} =
        conn
        |> Plug.Test.init_test_session(%{"session_id" => "admin-audience"})
        |> live("/r/#{audience_room.slug}")

      view = open_admin(conn)

      assert has_element?(view, "#total-live-visitors")
      assert render(view) =~ "1 live"

      count_html = view |> element("#room-live-#{audience_room.id}") |> render()
      assert count_html =~ "1"
      assert count_html =~ "250"
    end

    test "shows zero live visitors when no one is connected", %{conn: conn} do
      view = open_admin(conn)

      assert has_element?(view, "#total-live-visitors")
      assert render(view) =~ "0 live"
    end

    test "live updates the per-room column and total when a visitor joins", %{conn: conn} do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "live-update-room",
          "title" => "Live Update Room",
          "char_limit" => 320,
          "is_active" => true
        })

      # The admin page is already open (no visitors yet).
      view = open_admin(conn)
      assert view |> element("#room-live-#{room.id}") |> render() =~ "0"
      assert render(view) =~ "0 live"

      # A visitor joins after the admin page was opened.
      {:ok, _audience_view, _html} =
        conn
        |> Plug.Test.init_test_session(%{"session_id" => "live-update-audience"})
        |> live("/r/#{room.slug}")

      # The presence diff must reach the open admin LiveView and update the
      # streamed column live, without any reload from the admin side.
      assert_eventually(fn -> view |> element("#room-live-#{room.id}") |> render() =~ "1" end)
      assert_eventually(fn -> render(view) =~ "1 live" end)
    end
  end

  describe "room status toggle" do
    test "shows a per-row status switch and label in the rooms table", %{conn: conn} do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "status-room",
          "title" => "Status Room",
          "char_limit" => 320,
          "is_active" => true
        })

      view = open_admin(conn)

      assert has_element?(view, "#room-active-toggle-#{room.id}")
      html = view |> element("#room-active-toggle-#{room.id}") |> render()
      assert html =~ ~s(role="switch")
      assert html =~ ~s(aria-checked="true")
    end

    test "toggles a room between active and inactive from the rooms table", %{conn: conn} do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "toggle-room",
          "title" => "Toggle Room",
          "char_limit" => 320,
          "is_active" => true
        })

      view = open_admin(conn)

      view |> element(~s(#room-active-toggle-#{room.id})) |> render_click()
      refute Events.get_room!(room.id).is_active

      html = view |> element("#room-active-toggle-#{room.id}") |> render()
      assert html =~ ~s(aria-checked="false")

      view |> element(~s(#room-active-toggle-#{room.id})) |> render_click()
      assert Events.get_room!(room.id).is_active
    end

    test "create room modal can start a room as inactive", %{conn: conn} do
      view = open_admin(conn)
      view |> element(~s(button[phx-click="open_create_room"])) |> render_click()

      assert has_element?(view, ~s(#create-room-form input[name="room[is_active]"]))
      assert render(view) =~ ~s(id="room_is_active")

      view
      |> form("#create-room-form",
        room: %{
          "slug" => "inactive-new",
          "title" => "Inactive New",
          "moderator_id" => "",
          "char_limit" => "320",
          "expires_in" => "7 days",
          "is_active" => "false"
        }
      )
      |> render_submit()

      assert render(view) =~ "Room created successfully."
      assert Events.get_room_by_slug("inactive-new").is_active == false
    end

    test "configure room modal can change the active status", %{conn: conn} do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "config-toggle",
          "title" => "Config Toggle",
          "char_limit" => 320,
          "is_active" => true
        })

      view = open_admin(conn)
      view |> element(~s(button[phx-click="open_configure_room"])) |> render_click()

      view
      |> form("#configure-room-form",
        room: %{
          "title" => "Config Toggle",
          "slug" => "config-toggle",
          "char_limit" => "320",
          "is_active" => "false"
        }
      )
      |> render_submit()

      assert render(view) =~ "Room configured successfully."
      assert Events.get_room!(room.id).is_active == false
    end
  end

  defp assert_eventually(fun, timeout \\ 2_000) do
    if fun.() do
      :ok
    else
      if timeout <= 0 do
        flunk("condition not met within the expected timeout")
      else
        Process.sleep(20)
        assert_eventually(fun, timeout - 20)
      end
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

      view = open_admin(conn)

      assert has_element?(view, "#rooms-rows[phx-update=stream]")
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
