defmodule QaAppWeb.PageController do
  use QaAppWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  # Chrome's DevTools workspace probe. There is no workspace config to serve.
  def devtools(conn, _params), do: send_resp(conn, 204, "")
end
