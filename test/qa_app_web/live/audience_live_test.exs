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

  describe "inactive rooms" do
    defp open_inactive(conn, slug, session_id) do
      conn = Plug.Test.init_test_session(conn, %{"session_id" => session_id})
      {:ok, view, _html} = live(conn, "/r/#{slug}")
      view
    end

    test "counts a new visitor on the not ready view while keeping them connected", %{
      conn: conn,
      room: room
    } do
      room
      |> Ecto.Changeset.change(is_active: false)
      |> QaApp.Repo.update!()

      view = open_inactive(conn, room.slug, "waiting-session")

      assert has_element?(view, "#room-not-ready")
      refute has_element?(view, "#questions-feed")
      refute has_element?(view, "#question-form")

      # The visitor is tracked as a live visitor even while waiting.
      html = view |> element("#visitor-count") |> render()
      assert html =~ "1"
      assert html =~ "attending"
    end

    test "redirects to the full page when an inactive room is at capacity and the visitor is not counted",
         %{
           conn: conn,
           room: room
         } do
      room
      |> Ecto.Changeset.change(is_active: false, max_visitors: 1)
      |> QaApp.Repo.update!()

      {:ok, _view, _html} =
        conn
        |> Plug.Test.init_test_session(%{"session_id" => "fills-slot"})
        |> live("/r/#{room.slug}")

      assert_eventually(fn -> QaApp.RoomCapacity.count(room.id) == 1 end)

      conn =
        Plug.Test.init_test_session(Phoenix.ConnTest.build_conn(), %{
          "session_id" => "second-visitor"
        })

      full_path = "/r/#{room.slug}/full"
      assert {:error, {:redirect, %{to: ^full_path}}} = live(conn, "/r/#{room.slug}")

      # The second visitor was turned away, so only the first is counted.
      assert QaApp.RoomCapacity.count(room.id) == 1
    end

    test "does not expel live visitors when the room becomes inactive; shows the not ready view",
         %{
           conn: conn,
           room: room
         } do
      view = open_inactive(conn, room.slug, "stay-visitor")

      assert has_element?(view, "#questions-feed")
      assert_eventually(fn -> QaApp.RoomCapacity.count(room.id) == 1 end)

      {:ok, _} = Events.update_room(room, %{"is_active" => "false"})

      assert_eventually(fn -> has_element?(view, "#room-not-ready") end)
      refute has_element?(view, "#questions-feed")

      # The waiting visitor keeps their connection and stays counted.
      assert QaApp.RoomCapacity.count(room.id) == 1
    end

    test "shows questions again once the room is reactivated", %{conn: conn, room: room} do
      room
      |> Ecto.Changeset.change(is_active: false)
      |> QaApp.Repo.update!()

      view = open_inactive(conn, room.slug, "reactivate-visitor")

      assert has_element?(view, "#room-not-ready")

      {:ok, _} = Events.update_room(room, %{"is_active" => "true"})

      assert_eventually(fn -> has_element?(view, "#question-form") end)
      assert has_element?(view, "#questions-feed")
      assert view |> element("#questions-feed") |> render() =~ "How does this work"
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

    test "shows the not ready view for an inactive room without questions", %{
      conn: conn,
      room: room
    } do
      room
      |> Ecto.Changeset.change(is_active: false)
      |> QaApp.Repo.update!()

      html = html_response(get(conn, ~p"/r/#{room.slug}"), 200)

      assert html =~ "Room Not Ready"
      assert html =~ "isn't open yet"
      refute html =~ ~s(id="question-form")
      refute html =~ "How does this work"
      refute html =~ "Is this anonymous"
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

    test "another visitor's vote updates the feed row in place", %{conn: conn, room: room} do
      {:ok, question} =
        Engagement.create_question(room, "session-author", %{"content" => "Vote on me"})

      {:ok, view, _html} = open_as(conn, room.slug, "viewer-session")

      assert view
             |> element(~s(#q-#{question.id} button span.tabular-nums))
             |> render() =~ "0"

      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "another-voter")

      assert_eventually(fn ->
        view
        |> element(~s(#q-#{question.id} button span.tabular-nums))
        |> render() =~ "1"
      end)
    end

    test "an asked question is removed from the audience feed", %{conn: conn, room: room} do
      {:ok, question} =
        Engagement.create_question(room, "session-author", %{"content" => "Will be asked"})

      {:ok, view, _html} = open_as(conn, room.slug, "viewer-session")

      assert has_element?(view, "#questions-feed #q-#{question.id}")

      {:ok, _} = Engagement.mark_as_asked(question)

      assert_eventually(fn ->
        not has_element?(view, "#questions-feed #q-#{question.id}")
      end)
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
