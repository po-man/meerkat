defmodule QaApp.Repo.Migrations.CreateAppTables do
  use Ecto.Migration

  def change do
    # 1. accounts_users
    create table(:accounts_users, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :username, :string, null: false
      add :hashed_password, :string, null: false
      add :role, :string, null: false
      add :must_change_password, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts_users, [:username])

    # 2. events_rooms
    create table(:events_rooms, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :slug, :string, null: false
      add :title, :string, default: "Live Q&A", null: false
      add :intro_text, :text
      add :word_limit, :integer, default: 50, null: false
      add :is_active, :boolean, default: true, null: false
      add :admin_id, references(:accounts_users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:events_rooms, [:slug])
    create index(:events_rooms, [:admin_id])

    # 3. engagement_questions
    create table(:engagement_questions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :room_id, references(:events_rooms, type: :uuid, on_delete: :delete_all), null: false
      add :session_id, :string, null: false
      add :content, :text, null: false
      add :vote_count, :integer, default: 0, null: false
      add :is_asked, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:engagement_questions, [:room_id])
    create unique_index(:engagement_questions, [:room_id, :session_id])

    # 4. engagement_votes
    create table(:engagement_votes, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :question_id, references(:engagement_questions, type: :uuid, on_delete: :delete_all),
        null: false

      add :session_id, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:engagement_votes, [:question_id])
    create unique_index(:engagement_votes, [:question_id, :session_id])
  end
end
