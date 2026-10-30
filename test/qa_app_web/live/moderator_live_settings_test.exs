defmodule QaAppWeb.ModeratorLiveSettingsTest do
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

  describe "room settings page" do
    setup do
      {:ok, owner} =
        Accounts.create_moderator(%{"username" => "settings-owner", "password" => "secret123"})

      {:ok, room} =
        Events.create_room(%{
          "slug" => "settings-room",
          "title" => "Settings Room",
          "intro_text" => "Original intro",
          "char_limit" => 50,
          "is_active" => true,
          "moderator_id" => owner.id
        })

      {:ok, owner: owner, room: room}
    end

    test "renders the settings form with the current values and nav tabs", %{
      conn: conn,
      owner: owner,
      room: room
    } do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{room.slug}/settings")

      assert has_element?(view, "#settings-form")
      assert has_element?(view, "#room-tabs")
      assert has_element?(view, "#room-tab-settings")
      assert has_element?(view, "#room-tab-questions")
      assert has_element?(view, ~s(a[href="/moderator/r/#{room.slug}/export.csv"]))
      assert render(view) =~ ~s(id="sign-out")
      assert has_element?(view, "#room-expiry-local")
      assert render(view) =~ ~s(data-format="datetime")
      assert render(view) =~ ~s(phx-hook="LocalDateTime")

      # An active room shows no not-open banner on the settings page.
      refute has_element?(view, "#room-not-open-banner")
    end

    test "shows the not-open banner for an inactive room and opens it with one click", %{
      conn: conn,
      owner: owner,
      room: room
    } do
      room
      |> Ecto.Changeset.change(is_active: false)
      |> QaApp.Repo.update!()

      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{room.slug}/settings")

      assert has_element?(view, "#room-not-open-banner")
      assert has_element?(view, "#open-room-button")

      view |> element("#open-room-button") |> render_click()

      assert Events.get_room!(room.id).is_active == true

      # The banner clears and the "Room is open" toggle reflects the new state.
      refute has_element?(view, "#room-not-open-banner")

      toggle_html =
        view
        |> element(~s(#settings-form input[type=checkbox][name="room[is_active]"]))
        |> render()

      assert toggle_html =~ "checked"
    end

    test "updates the room settings on submit", %{conn: conn, owner: owner, room: room} do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{room.slug}/settings")

      view
      |> form("#settings-form",
        room: %{
          "title" => "New Title",
          "intro_text" => "New intro",
          "char_limit" => "75"
        }
      )
      |> render_submit()

      assert render(view) =~ "Room settings updated successfully."

      updated_room = Events.get_room!(room.id)
      assert updated_room.title == "New Title"
      assert updated_room.intro_text == "New intro"
      assert updated_room.char_limit == 75
    end

    test "shows validation errors for an invalid character limit", %{
      conn: conn,
      owner: owner,
      room: room
    } do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{room.slug}/settings")

      html =
        view
        |> form("#settings-form", room: %{"title" => "Valid Title", "char_limit" => "0"})
        |> render_submit()

      assert html =~ "must be greater than 0"
    end

    test "updates the max visitors limit on submit", %{conn: conn, owner: owner, room: room} do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{room.slug}/settings")

      view
      |> form("#settings-form",
        room: %{
          "title" => "New Title",
          "max_visitors" => "120"
        }
      )
      |> render_submit()

      assert render(view) =~ "Room settings updated successfully."
      assert Events.get_room!(room.id).max_visitors == 120
    end

    test "accepts an empty max visitors as unlimited", %{conn: conn, owner: owner, room: room} do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{room.slug}/settings")

      view
      |> form("#settings-form", room: %{"title" => "New Title", "max_visitors" => ""})
      |> render_submit()

      assert render(view) =~ "Room settings updated successfully."
      assert is_nil(Events.get_room!(room.id).max_visitors)
    end

    test "rejects a max visitors below 1", %{conn: conn, owner: owner, room: room} do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{room.slug}/settings")

      html =
        view
        |> form("#settings-form", room: %{"title" => "Valid Title", "max_visitors" => "0"})
        |> render_submit()

      assert html =~ "must be at least 1"
    end

    test "toggles the room active status via the settings form", %{
      conn: conn,
      owner: owner,
      room: room
    } do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{room.slug}/settings")

      assert has_element?(view, ~s(#settings-form input[name="room[is_active]"]))

      view
      |> form("#settings-form", room: %{"title" => "Valid Title", "is_active" => "false"})
      |> render_submit()

      assert render(view) =~ "Room settings updated successfully."
      assert Events.get_room!(room.id).is_active == false
    end

    test "shows the live visitor count and updates it as visitors join", %{
      conn: conn,
      owner: owner,
      room: room
    } do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{room.slug}/settings")

      assert has_element?(view, "#moderator-visitor-count")

      html = view |> element("#moderator-visitor-count") |> render()
      assert html =~ "0"
      assert html =~ "live"

      # A visitor joins while the settings page is open; the count updates live.
      {:ok, _audience_view, _html} =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{"session_id" => "settings-visitor"})
        |> live("/r/#{room.slug}")

      assert_eventually(fn ->
        view |> element("#moderator-visitor-count") |> render() =~ "1"
      end)
    end

    test "redirects a moderator who does not own the room", %{conn: conn, room: room} do
      {:ok, other} =
        Accounts.create_moderator(%{"username" => "other-mod", "password" => "secret123"})

      conn = login_as(conn, other.username)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/moderator/r/#{room.slug}/settings")
    end

    test "redirects anonymous visitors to sign in", %{conn: conn, room: room} do
      conn = get(conn, "/moderator/r/#{room.slug}/settings")
      assert redirected_to(conn) == AdminAuth.secret_path()
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
end
