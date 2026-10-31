defmodule QaAppWeb.PageControllerTest do
  use QaAppWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Real-Time Anonymous Q"
  end

  test "does not link to the admin sign-in page", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    refute html =~ QaAppWeb.AdminAuth.secret_path()
    refute html =~ "Admin Login"
  end

  test "answers the Chrome DevTools probe with 204", %{conn: conn} do
    conn = get(conn, "/.well-known/appspecific/com.chrome.devtools.json")

    assert conn.status == 204
    assert conn.resp_body == ""
  end
end
