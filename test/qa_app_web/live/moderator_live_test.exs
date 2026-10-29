defmodule QaAppWeb.ModeratorLiveTest do
  use QaAppWeb.ConnCase

  import Phoenix.LiveViewTest

  alias QaApp.Accounts
  alias QaApp.Engagement
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

  describe "header sign-out on protected pages" do
    test "is shown on the moderator dashboard", %{conn: conn} do
      conn = login_as(conn, "mod")

      html = html_response(get(conn, "/moderator/dashboard"), 200)
      assert html =~ ~s(id="sign-out")
      assert html =~ "Sign Out"
      assert html =~ "mod"
    end

    test "is shown on the room moderator page", %{conn: conn} do
      {:ok, owner} =
        Accounts.create_moderator(%{"username" => "owner", "password" => "secret123"})

      {:ok, room} =
        Events.create_room(%{
          "slug" => "townhall",
          "title" => "Town Hall",
          "char_limit" => 320,
          "is_active" => true,
          "moderator_id" => owner.id
        })

      conn = login_as(conn, "owner")

      html = html_response(get(conn, "/moderator/r/#{room.slug}"), 200)
      assert html =~ ~s(id="sign-out")
      assert html =~ "Sign Out"
    end

    test "is shown on the admin dashboard", %{conn: conn} do
      conn = login_as(conn, "root")

      html = html_response(get(conn, "/admin"), 200)
      assert html =~ ~s(id="sign-out")
      assert html =~ "Sign Out"
    end

    test "is not shown to anonymous visitors (they are redirected to sign in)", %{conn: conn} do
      conn = get(conn, "/moderator/dashboard")
      assert redirected_to(conn) == AdminAuth.secret_path()

      conn = get(conn, "/admin")
      assert redirected_to(conn) == AdminAuth.secret_path()
    end
  end

  describe "moderation pages render with live content" do
    setup do
      {:ok, owner} =
        Accounts.create_moderator(%{"username" => "moder", "password" => "secret123"})

      {:ok, room} =
        Events.create_room(%{
          "slug" => "render-room",
          "title" => "Render Room",
          "char_limit" => 320,
          "is_active" => true,
          "moderator_id" => owner.id
        })

      {:ok, _} =
        Engagement.create_question(room, "audience-1", %{"content" => "Queue this question"})

      {:ok, owner: owner, room: room}
    end

    test "room dashboard lists the assigned room", %{conn: conn, owner: owner} do
      conn = login_as(conn, owner.username)

      html = html_response(get(conn, "/moderator/dashboard"), 200)
      assert html =~ "Render Room"
      assert html =~ "/r/render-room"
      assert html =~ ~s(id="moderator-rooms")
    end

    test "moderator page shows the question queue", %{conn: conn, owner: owner, room: room} do
      conn = login_as(conn, owner.username)

      html = html_response(get(conn, "/moderator/r/#{room.slug}"), 200)
      assert html =~ "Queue this question"
      assert html =~ ~s(id="moderator-questions-feed")
    end
  end

  describe "raised and asked question tabs" do
    setup do
      {:ok, owner} =
        Accounts.create_moderator(%{"username" => "moder", "password" => "secret123"})

      {:ok, room} =
        Events.create_room(%{
          "slug" => "tab-room",
          "title" => "Tab Room",
          "char_limit" => 320,
          "is_active" => true,
          "moderator_id" => owner.id
        })

      {:ok, raised_question} =
        Engagement.create_question(room, "audience-1", %{"content" => "Question still raised"})

      {:ok, asked_question} =
        Engagement.create_question(room, "audience-2", %{"content" => "Question already asked"})

      {:ok, asked_question} = Engagement.mark_as_asked(asked_question)

      {:ok,
       owner: owner, room: room, raised_question: raised_question, asked_question: asked_question}
    end

    defp open_room(conn, owner, slug, query \\ "") do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{slug}#{query}")
      view
    end

    test "shows the raised questions tab by default", %{
      conn: conn,
      owner: owner,
      room: room,
      raised_question: raised_question,
      asked_question: asked_question
    } do
      view = open_room(conn, owner, room.slug)

      assert has_element?(view, "#moderator-tabs")
      assert has_element?(view, "#moderator-tab-raised")
      assert has_element?(view, "#moderator-tab-asked")
      assert has_element?(view, "#raised-questions-feed[phx-update=stream]")
      assert has_element?(view, "#raised-questions-feed #moderator-q-#{raised_question.id}")
      refute has_element?(view, "#raised-questions-feed #moderator-q-#{asked_question.id}")
      refute has_element?(view, "#asked-questions-feed")
    end

    test "switches to the asked questions tab", %{
      conn: conn,
      owner: owner,
      room: room,
      raised_question: raised_question,
      asked_question: asked_question
    } do
      view = open_room(conn, owner, room.slug)

      view |> element("#moderator-tab-asked") |> render_click()

      assert has_element?(view, "#asked-questions-feed")
      assert has_element?(view, "#asked-questions-feed #moderator-q-#{asked_question.id}")
      refute has_element?(view, "#asked-questions-feed #moderator-q-#{raised_question.id}")
      refute has_element?(view, "#raised-questions-feed")
    end

    test "loads the asked tab directly via the tab query param", %{
      conn: conn,
      owner: owner,
      room: room,
      asked_question: asked_question
    } do
      view = open_room(conn, owner, room.slug, "?tab=asked")

      assert has_element?(view, "#asked-questions-feed")
      assert has_element?(view, "#asked-questions-feed #moderator-q-#{asked_question.id}")
    end

    test "marking a raised question as asked moves it to the asked tab", %{
      conn: conn,
      owner: owner,
      room: room,
      raised_question: raised_question
    } do
      view = open_room(conn, owner, room.slug)

      view
      |> element(~s(#moderator-q-#{raised_question.id} button[phx-click="mark_asked"]))
      |> render_click()

      refute has_element?(view, "#raised-questions-feed #moderator-q-#{raised_question.id}")

      view |> element("#moderator-tab-asked") |> render_click()

      assert has_element?(view, "#asked-questions-feed #moderator-q-#{raised_question.id}")
    end

    test "moving an asked question back to raised returns it to the raised tab", %{
      conn: conn,
      owner: owner,
      room: room,
      asked_question: asked_question
    } do
      view = open_room(conn, owner, room.slug, "?tab=asked")

      assert has_element?(view, "#asked-questions-feed #moderator-q-#{asked_question.id}")

      view
      |> element(~s(#moderator-q-#{asked_question.id} button[phx-click="mark_unasked"]))
      |> render_click()

      refute has_element?(view, "#asked-questions-feed #moderator-q-#{asked_question.id}")

      view |> element("#moderator-tab-raised") |> render_click()

      assert has_element?(view, "#raised-questions-feed #moderator-q-#{asked_question.id}")
    end
  end

  describe "moderator page navigation tabs" do
    setup do
      {:ok, owner} =
        Accounts.create_moderator(%{"username" => "nav-owner", "password" => "secret123"})

      {:ok, room} =
        Events.create_room(%{
          "slug" => "nav-room",
          "title" => "Nav Room",
          "char_limit" => 320,
          "is_active" => true,
          "moderator_id" => owner.id
        })

      {:ok, owner: owner, room: room}
    end

    test "moderator page shows the Questions and Settings tabs", %{
      conn: conn,
      owner: owner,
      room: room
    } do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{room.slug}")

      assert has_element?(view, "#room-tabs")
      assert has_element?(view, "#room-tab-questions")
      assert has_element?(view, "#room-tab-settings")
    end

    test "navigating to the Settings tab opens the settings page", %{
      conn: conn,
      owner: owner,
      room: room
    } do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{room.slug}")

      result = view |> element("#room-tab-settings") |> render_click()

      {:ok, view, _html} = follow_redirect(result, conn)

      assert has_element?(view, "#settings-form")
      assert has_element?(view, "#room-tab-settings")
    end
  end

  describe "live visitor count" do
    setup do
      {:ok, owner} =
        Accounts.create_moderator(%{"username" => "count-owner", "password" => "secret123"})

      {:ok, room} =
        Events.create_room(%{
          "slug" => "count-room",
          "title" => "Count Room",
          "char_limit" => 320,
          "is_active" => true,
          "max_visitors" => "200",
          "moderator_id" => owner.id
        })

      {:ok, owner: owner, room: room}
    end

    test "shows the live visitor count and capacity on the room page", %{
      conn: conn,
      owner: owner,
      room: room
    } do
      conn = login_as(conn, owner.username)
      {:ok, view, _html} = live(conn, "/moderator/r/#{room.slug}")

      assert has_element?(view, "#moderator-visitor-count")

      html = view |> element("#moderator-visitor-count") |> render()
      assert html =~ "0"
      assert html =~ "live"
      assert html =~ "200"
    end
  end
end
