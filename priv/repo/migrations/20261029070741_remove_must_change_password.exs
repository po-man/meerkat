defmodule QaApp.Repo.Migrations.RemoveMustChangePassword do
  use Ecto.Migration

  def change do
    alter table(:accounts_users) do
      remove :must_change_password
    end
  end
end