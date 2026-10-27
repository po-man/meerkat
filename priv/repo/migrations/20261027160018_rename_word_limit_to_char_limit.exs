defmodule QaApp.Repo.Migrations.RenameWordLimitToCharLimit do
  use Ecto.Migration

  # SQLite3 does not support ALTER COLUMN, so renaming the column and
  # updating its default requires recreating the table.

  def up do
    create table(:events_rooms_new, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :slug, :string, null: false
      add :title, :string, default: "Live Q&A", null: false
      add :intro_text, :text
      add :char_limit, :integer, default: 320, null: false
      add :is_active, :boolean, default: true, null: false
      add :admin_id, references(:accounts_users, type: :uuid, on_delete: :nilify_all)
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    execute("""
    INSERT INTO events_rooms_new
      (id, slug, title, intro_text, char_limit, is_active, admin_id, inserted_at, updated_at, expires_at)
    SELECT id, slug, title, intro_text, word_limit, is_active, admin_id, inserted_at, updated_at, expires_at
    FROM events_rooms
    """)

    drop table(:events_rooms)
    rename table(:events_rooms_new), to: table(:events_rooms)

    create unique_index(:events_rooms, [:slug])
    create index(:events_rooms, [:admin_id])
  end

  def down do
    create table(:events_rooms_old, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :slug, :string, null: false
      add :title, :string, default: "Live Q&A", null: false
      add :intro_text, :text
      add :word_limit, :integer, default: 50, null: false
      add :is_active, :boolean, default: true, null: false
      add :admin_id, references(:accounts_users, type: :uuid, on_delete: :nilify_all)
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    execute("""
    INSERT INTO events_rooms_old
      (id, slug, title, intro_text, word_limit, is_active, admin_id, inserted_at, updated_at, expires_at)
    SELECT id, slug, title, intro_text, char_limit, is_active, admin_id, inserted_at, updated_at, expires_at
    FROM events_rooms
    """)

    drop table(:events_rooms)
    rename table(:events_rooms_old), to: table(:events_rooms)

    create unique_index(:events_rooms, [:slug])
    create index(:events_rooms, [:admin_id])
  end
end
