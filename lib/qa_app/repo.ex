defmodule QaApp.Repo do
  use Ecto.Repo,
    otp_app: :qa_app,
    adapter: Application.compile_env(:qa_app, :ecto_adapter, Ecto.Adapters.SQLite3)
end
