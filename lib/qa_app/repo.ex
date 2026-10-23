defmodule QaApp.Repo do
  use Ecto.Repo,
    otp_app: :qa_app,
    adapter: Ecto.Adapters.SQLite3
end
