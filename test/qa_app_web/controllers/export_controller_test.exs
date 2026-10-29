defmodule QaAppWeb.ExportControllerTest do
  use QaAppWeb.ConnCase

  alias QaApp.Accounts
  alias QaApp.Engagement
  alias QaApp.Events
  alias QaAppWeb.AdminAuth

  @secret_path AdminAuth.secret_path()

  setup do
    {:ok, _} = Accounts.create_admin(%{"username" => "root", "password" => "secret123"})
    :ok
  end

  defp login_as(conn, username) do
    post(conn, @secret_path, %{"username" => username, "password" => "secret123"})
  end

  defp create_room(moderator) do
    {:ok, room} =
      Events.create_room(%{
        "slug" => "export-room",
        "title" => "Export Room",
        "char_limit" => 320,
        "is_active" => true,
        "moderator_id" => moderator && moderator.id
      })

    room
  end

  test "QR png is served to an authenticated user", %{conn: conn} do
    conn = login_as(conn, "root")

    conn = get(conn, ~p"/moderator/r/my-room/qr.png")

    assert conn.status == 200
    assert response_content_type(conn, :png)

    # A PNG file must start with its magic signature
    assert <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = conn.resp_body
  end

  describe "csv export" do
    test "redirects anonymous visitors to sign in", %{conn: conn} do
      conn = get(conn, ~p"/moderator/r/export-room/export.csv")
      assert redirected_to(conn) == @secret_path
    end

    test "rejects a moderator who does not own the room", %{conn: conn} do
      {:ok, _} = Accounts.create_moderator(%{"username" => "other", "password" => "secret123"})
      create_room(nil)

      conn = login_as(conn, "other")
      conn = get(conn, ~p"/moderator/r/export-room/export.csv")

      assert redirected_to(conn) == "/"
    end

    test "exports only trimmed question columns for the room owner", %{conn: conn} do
      {:ok, owner} =
        Accounts.create_moderator(%{"username" => "owner", "password" => "secret123"})

      room = create_room(owner)

      {:ok, _} =
        Engagement.create_question(room, "session-1", %{"content" => "What about csv"})

      conn = login_as(conn, "owner")
      conn = get(conn, ~p"/moderator/r/#{room.slug}/export.csv")

      assert conn.status == 200
      assert response_content_type(conn, :csv)
      assert conn.resp_body =~ "Submitted At,Content,Vote Count,Is Asked"
      assert conn.resp_body =~ ~s("What about csv")
      # Do not leak internal or audience identifiers.
      refute conn.resp_body =~ "Session ID"
      refute conn.resp_body =~ "session-1"
    end
  end
end
