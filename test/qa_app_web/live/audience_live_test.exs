defmodule QaAppWeb.AudienceLiveTest do
  use QaAppWeb.ConnCase

  import Phoenix.LiveViewTest

  alias QaApp.Events
  alias QaApp.Engagement

  setup do
    {:ok, room} =
      Events.create_room(%{
        "slug" => "townhall",
        "title" => "Town Hall",
        "char_limit" => 320,
        "is_active" => true
      })

    {:ok, _} = Engagement.create_question(room, "session-a", %{"content" => "How does this work"})
    {:ok, _} = Engagement.create_question(room, "session-b", %{"content" => "Is this anonymous"})

    {:ok, room: room}
  end

  test "renders the room page with the question feed", %{conn: conn, room: room} do
    html = html_response(get(conn, ~p"/r/#{room.slug}"), 200)

    assert html =~ "Town Hall"
    assert html =~ "How does this work"
    assert html =~ "Is this anonymous"
    assert html =~ ~s(id="questions-feed")
    assert html =~ ~s(id="question-form")
    assert html =~ ~s(data-format="time")
    assert html =~ ~s(phx-hook="LocalDateTime")
  end

  describe "live visitors" do
    test "shows the live visitor count in the masthead", %{conn: conn, room: room} do
      conn = Plug.Test.init_test_session(conn, %{"session_id" => "audience-count"})
      {:ok, view, _html} = live(conn, "/r/#{room.slug}")

      assert has_element?(view, "#visitor-count")

      html = view |> element("#visitor-count") |> render()
      assert html =~ "1"
      assert html =~ "attending"
    end

    test "redirects new visitors to the full page when the room is at capacity", %{
      conn: conn,
      room: room
    } do
      room
      |> Ecto.Changeset.change(max_visitors: 1)
      |> QaApp.Repo.update!()

      {:ok, _view, _html} =
        conn
        |> Plug.Test.init_test_session(%{"session_id" => "audience-a"})
        |> live("/r/#{room.slug}")

      conn =
        Plug.Test.init_test_session(Phoenix.ConnTest.build_conn(), %{
          "session_id" => "audience-b"
        })

      full_path = "/r/#{room.slug}/full"

      assert {:error, {:redirect, %{to: ^full_path}}} = live(conn, "/r/#{room.slug}")
    end

    test "redirects a visitor to the full page when they are expelled", %{
      conn: conn,
      room: room
    } do
      {:ok, view, _html} =
        conn
        |> Plug.Test.init_test_session(%{"session_id" => "session-me"})
        |> live("/r/#{room.slug}")

      Phoenix.PubSub.broadcast(
        QaApp.PubSub,
        "room:#{room.id}",
        {:room_visitors_expelled, ["session-me"]}
      )

      assert_redirect(view, "/r/#{room.slug}/full")
    end
  end

  describe "current user's submitted question" do
    defp open_as(conn, slug, session_id) do
      conn = Plug.Test.init_test_session(conn, %{"session_id" => session_id})
      live(conn, "/r/#{slug}")
    end

    test "renders the question feed as a live stream", %{conn: conn, room: room} do
      {:ok, view, _html} = open_as(conn, room.slug, "audience-0")

      assert has_element?(view, "#questions-feed[phx-update=stream]")
    end

    test "redirects from an inactive room", %{conn: conn, room: room} do
      room
      |> Ecto.Changeset.change(is_active: false)
      |> QaApp.Repo.update!()

      conn = get(conn, ~p"/r/#{room.slug}")

      assert redirected_to(conn) == "/"
    end

    test "an upvote toggles the button's selected state", %{conn: conn, room: room} do
      {:ok, vote_question} =
        Engagement.create_question(room, "voter-session", %{"content" => "Toggle me"})

      {:ok, view, _html} = open_as(conn, room.slug, "current-session")

      assert has_element?(view, ~s(#q-#{vote_question.id} button[phx-click="toggle_vote"]))
      refute has_element?(view, ~s(#q-#{vote_question.id} button.bg-ink))

      view
      |> element(~s(#q-#{vote_question.id} button[phx-click="toggle_vote"]))
      |> render_click()

      assert has_element?(view, ~s(#q-#{vote_question.id} button.bg-ink))
    end

    test "shows the Raised status and upvote count beside the submitted question", %{
      conn: conn,
      room: room
    } do
      {:ok, question} =
        Engagement.create_question(room, "session-me", %{"content" => "My question"})

      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter-1")
      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter-2")

      {:ok, view, html} = open_as(conn, room.slug, "session-me")

      assert html =~ "Question Submitted"
      assert html =~ "My question"
      assert has_element?(view, "#user-question-status")
      assert view |> element("#user-question-status") |> render() =~ "Raised"
      assert view |> element("#user-question-vote-count") |> render() =~ "2"
      assert view |> element("#user-question-vote-count") |> render() =~ "upvotes"
    end

    test "updates the status to Asked when a moderator marks the question as asked", %{
      conn: conn,
      room: room
    } do
      {:ok, question} =
        Engagement.create_question(room, "session-me", %{"content" => "My question"})

      {:ok, view, _html} = open_as(conn, room.slug, "session-me")

      assert view |> element("#user-question-status") |> render() =~ "Raised"

      {:ok, _} = question |> Engagement.mark_as_asked()

      assert view |> element("#user-question-status") |> render() =~ "Asked"
    end

    test "highlights the current user's own row in the audience feed", %{
      conn: conn,
      room: room
    } do
      {:ok, question} =
        Engagement.create_question(room, "session-me", %{"content" => "My question"})

      {:ok, view, _html} = open_as(conn, room.slug, "session-me")

      assert has_element?(view, "#questions-feed #q-#{question.id}")
      assert has_element?(view, "#your-question-#{question.id}")
      refute has_element?(view, ~s(#q-#{question.id} button[phx-click="toggle_vote"]))
    end
  end
end
