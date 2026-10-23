defmodule QaAppWeb.Plugs.SessionId do
  import Plug.Conn

  @cookie_name "_qa_app_anonymous_session"

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :session_id) || conn.cookies[@cookie_name] do
      nil ->
        session_id = Ecto.UUID.generate()

        conn
        |> put_session(:session_id, session_id)
        |> put_resp_cookie(@cookie_name, session_id,
          max_age: 60 * 60 * 24 * 365,
          http_only: true,
          same_site: "Lax"
        )
        |> assign(:session_id, session_id)

      session_id ->
        conn
        |> put_session(:session_id, session_id)
        |> assign(:session_id, session_id)
    end
  end
end
