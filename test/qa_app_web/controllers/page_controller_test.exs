defmodule QaAppWeb.PageControllerTest do
  use QaAppWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Real-Time Anonymous Q"
  end

  test "renders the meerkat key visual", %{conn: conn} do
    document =
      conn
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_fragment()

    # The visual is decorative, so it must stay out of the accessibility tree.
    assert document |> LazyHTML.query(~s([data-meerkat][aria-hidden="true"])) |> Enum.count() == 1

    # Every layer the animation layer targets must exist exactly once: the CSS
    # ambient motion and the JS beats both address these hooks by name.
    for part <- ~w(ambient leg-back leg-front tail arm-raised torso-front torso-back arm-near
                   head-unit ears ear-left ear-right face eyes eye-left eye-right pupil-left
                   pupil-right) do
      assert document |> LazyHTML.query(~s([data-part="#{part}"])) |> Enum.count() == 1,
             "expected exactly one #{part} group in the meerkat"
    end
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
