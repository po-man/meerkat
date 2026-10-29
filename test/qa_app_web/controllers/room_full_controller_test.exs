defmodule QaAppWeb.RoomFullControllerTest do
  use QaAppWeb.ConnCase

  alias QaApp.Events

  describe "GET /r/:slug/full" do
    test "renders the room full page with a refresh header and retry link" do
      {:ok, _room} =
        Events.create_room(%{
          "slug" => "full-room",
          "title" => "Full Room",
          "is_active" => true,
          "expires_in" => "1 hour"
        })

      conn = get(build_conn(), "/r/full-room/full")

      # The Refresh header makes the page re-check the room without keeping a
      # WebSocket open (see RoomFullController @moduledoc).
      assert Plug.Conn.get_resp_header(conn, "refresh") == ["20; url=/r/full-room"]

      html = html_response(conn, 200)
      assert html =~ "This room is at capacity"
      assert html =~ "Full Room"
      assert html =~ ~s(href="/r/full-room")
    end

    test "redirects home for an unknown room" do
      conn = get(build_conn(), "/r/unknown/full")
      assert redirected_to(conn) == "/"
    end

    test "redirects home for an inactive room" do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "dead-room",
          "title" => "Dead Room",
          "is_active" => true,
          "expires_in" => "1 hour"
        })

      room
      |> Ecto.Changeset.change(is_active: false)
      |> QaApp.Repo.update!()

      conn = get(build_conn(), "/r/dead-room/full")
      assert redirected_to(conn) == "/"
    end
  end
end
