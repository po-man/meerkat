defmodule QaApp.Repo.Migrations.RenameRolesToAdminAndModerator do
  use Ecto.Migration

  def change do
    execute(
      "UPDATE accounts_users SET role = 'admin' WHERE role = 'super_admin'",
      "UPDATE accounts_users SET role = 'super_admin' WHERE role = 'admin'"
    )

    execute(
      "UPDATE accounts_users SET role = 'moderator' WHERE role = 'room_admin'",
      "UPDATE accounts_users SET role = 'room_admin' WHERE role = 'moderator'"
    )

    rename table(:events_rooms), :admin_id, to: :moderator_id
  end
end
