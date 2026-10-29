defmodule QaApp.Repo.Migrations.AddMaxVisitorsToRooms do
  use Ecto.Migration

  def change do
    alter table(:events_rooms) do
      # nil means "unlimited"; a positive integer is the max concurrent visitors.
      add :max_visitors, :integer, default: 250
    end
  end
end
