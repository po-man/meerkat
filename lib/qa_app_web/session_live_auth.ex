defmodule QaAppWeb.SessionLiveAuth do
  import Phoenix.Component

  def on_mount(_stage, _params, session, socket) do
    session_id =
      session["session_id"] || session["_qa_app_anonymous_session"] || Ecto.UUID.generate()

    {:cont, assign(socket, :session_id, session_id)}
  end
end
