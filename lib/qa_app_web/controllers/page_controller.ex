defmodule QaAppWeb.PageController do
  use QaAppWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
