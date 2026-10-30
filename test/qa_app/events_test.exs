defmodule QaApp.EventsTest do
  use QaApp.DataCase

  alias QaApp.Events
  alias QaApp.Events.Room

  import Ecto.Changeset

  describe "create_room/1" do
    test "defaults to a 7 day expiry when no duration is given" do
      assert {:ok, room} =
               Events.create_room(%{
                 "slug" => "default-expiry",
                 "title" => "Default Expiry"
               })

      expected = DateTime.add(DateTime.utc_now(), 7 * 24 * 60 * 60, :second)
      assert DateTime.diff(room.expires_at, expected) |> abs() < 5
    end

    test "computes the expiry from the chosen duration" do
      assert {:ok, room} =
               Events.create_room(%{
                 "slug" => "short-expiry",
                 "title" => "Short Expiry",
                 "expires_in" => "30 minutes"
               })

      expected = DateTime.add(DateTime.utc_now(), 30 * 60, :second)
      assert DateTime.diff(room.expires_at, expected) |> abs() < 5
    end

    test "rejects an expiry that is not one of the allowed options" do
      assert {:error, changeset} =
               Events.create_room(%{
                 "slug" => "bad-expiry",
                 "title" => "Bad Expiry",
                 "expires_in" => "2 weeks"
               })

      assert %{expires_in: ["is not a valid option"]} = errors_on(changeset)
    end

    test "requires an expiry to be selected" do
      assert {:error, changeset} =
               Events.create_room(%{
                 "slug" => "no-expiry",
                 "title" => "No Expiry",
                 "expires_in" => ""
               })

      assert "must be selected" in errors_on(changeset).expires_in
    end

    test "defaults to active when not provided" do
      assert {:ok, room} =
               Events.create_room(%{
                 "slug" => "active-default",
                 "title" => "Active Default",
                 "expires_in" => "1 hour"
               })

      assert room.is_active == true
    end

    test "accepts an explicit inactive status" do
      assert {:ok, room} =
               Events.create_room(%{
                 "slug" => "inactive-create",
                 "title" => "Inactive Create",
                 "is_active" => "false",
                 "expires_in" => "1 hour"
               })

      assert room.is_active == false
    end
  end

  describe "update_room/2" do
    test "does not allow changing the expiry after creation" do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "locked-expiry",
          "title" => "Locked Expiry",
          "expires_in" => "1 hour"
        })

      original_expiry = room.expires_at

      assert {:ok, updated_room} =
               Events.update_room(room, %{
                 "title" => "Renamed",
                 "expires_in" => "7 days",
                 "expires_at" => "2030-01-01 00:00:00"
               })

      assert updated_room.title == "Renamed"
      assert updated_room.expires_at == original_expiry
    end
  end

  describe "max_visitors" do
    test "defaults to 250 when not provided" do
      assert {:ok, room} =
               Events.create_room(%{
                 "slug" => "max-default",
                 "title" => "Max Default",
                 "expires_in" => "1 hour"
               })

      assert room.max_visitors == 250
    end

    test "accepts an explicit visitor limit" do
      assert {:ok, room} =
               Events.create_room(%{
                 "slug" => "max-custom",
                 "title" => "Max Custom",
                 "expires_in" => "1 hour",
                 "max_visitors" => "50"
               })

      assert room.max_visitors == 50
    end

    test "treats an empty value as unlimited" do
      assert {:ok, room} =
               Events.create_room(%{
                 "slug" => "max-unlimited",
                 "title" => "Max Unlimited",
                 "expires_in" => "1 hour",
                 "max_visitors" => ""
               })

      assert is_nil(room.max_visitors)
    end

    test "rejects limits below 1" do
      assert {:error, changeset} =
               Events.create_room(%{
                 "slug" => "max-zero",
                 "title" => "Max Zero",
                 "expires_in" => "1 hour",
                 "max_visitors" => "0"
               })

      assert %{max_visitors: ["must be at least 1"]} = errors_on(changeset)
    end

    test "rejects negative limits" do
      assert {:error, changeset} =
               Events.create_room(%{
                 "slug" => "max-negative",
                 "title" => "Max Negative",
                 "expires_in" => "1 hour",
                 "max_visitors" => "-5"
               })

      assert %{max_visitors: ["must be at least 1"]} = errors_on(changeset)
    end

    test "rejects non numeric values" do
      assert {:error, changeset} =
               Events.create_room(%{
                 "slug" => "max-invalid",
                 "title" => "Max Invalid",
                 "expires_in" => "1 hour",
                 "max_visitors" => "lots"
               })

      assert %{max_visitors: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "cleanup_expired_rooms/0" do
    test "deletes only rooms whose expiry is in the past" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      expired_room = insert_room!(%{slug: "expired-cleanup", expires_at: past})
      future_room = insert_room!(%{slug: "future-cleanup", expires_at: future})

      assert Enum.map(Events.cleanup_expired_rooms(), & &1.id) == [expired_room.id]

      refute Repo.get(Room, expired_room.id)
      assert Repo.get(Room, future_room.id)
    end
  end

  describe "next_room_expiry/0" do
    test "returns the room with the soonest upcoming expiry" do
      later = DateTime.add(DateTime.utc_now(), 3600, :second)
      sooner = DateTime.add(DateTime.utc_now(), 300, :second)

      _later_room = insert_room!(%{slug: "expiry-later", expires_at: later})
      sooner_room = insert_room!(%{slug: "expiry-sooner", expires_at: sooner})

      assert Events.next_room_expiry().id == sooner_room.id
    end

    test "returns nil when no room has an upcoming expiry" do
      insert_room!(%{
        slug: "expiry-past",
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })

      assert is_nil(Events.next_room_expiry())
    end
  end

  defp insert_room!(attrs) do
    attrs = Map.update(attrs, :expires_at, nil, &DateTime.truncate(&1, :second))

    %Room{}
    |> change(attrs)
    |> Repo.insert!()
  end
end
