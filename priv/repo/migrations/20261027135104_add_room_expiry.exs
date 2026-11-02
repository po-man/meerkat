defmodule QaApp.Repo.Migrations.AddRoomExpiry do
  use Ecto.Migration

  def change do
    alter table(:events_rooms) do
      add :expires_at, :utc_datetime
    end

    # Existing rooms expire 1 day after they were inserted. SQLite and Postgres
    # spell date arithmetic differently.
    if postgres?() do
      execute("""
      UPDATE events_rooms
      SET expires_at = inserted_at + interval '1 day'
      """)
    else
      execute("""
      UPDATE events_rooms
      SET expires_at = datetime(inserted_at, '+1 day')
      """)
    end
  end

  defp postgres?, do: repo().__adapter__() == Ecto.Adapters.Postgres
end
