defmodule QaAppWeb.PageControllerTest do
  use QaAppWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Real-Time Anonymous Q"
  end
end
