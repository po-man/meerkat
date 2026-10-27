defmodule QaAppWeb.AudienceLiveTest do
  use QaAppWeb.ConnCase

  alias QaApp.Events
  alias QaApp.Engagement

  setup do
    {:ok, room} =
      Events.create_room(%{
        "slug" => "townhall",
        "title" => "Town Hall",
        "word_limit" => 50,
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
  end
end
