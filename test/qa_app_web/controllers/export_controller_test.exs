defmodule QaAppWeb.ExportControllerTest do
  use QaAppWeb.ConnCase

  test "GET /moderator/r/:slug/qr.png returns a valid PNG image", %{conn: conn} do
    conn = get(conn, ~p"/moderator/r/my-room/qr.png")

    assert conn.status == 200
    assert response_content_type(conn, :png)

    # A PNG file must start with its magic signature
    assert <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = conn.resp_body
  end
end
