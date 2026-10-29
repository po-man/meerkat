defmodule QaApp.Events do
  @moduledoc """
  The Events context for managing event rooms.
  """

  import Ecto.Query, warn: false
  alias QaApp.Repo
  alias QaApp.Events.Room
  alias QaApp.RoomExpiryScheduler

  @default_expiry_in "7 days"

  def list_rooms do
    Room
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
    |> Repo.preload(:moderator)
  end

  def list_rooms_for_moderator(moderator_id) when not is_nil(moderator_id) do
    Room
    |> where([r], r.moderator_id == ^moderator_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
    |> Repo.preload(:moderator)
  end

  def get_room!(id) do
    Room
    |> Repo.get!(id)
    |> Repo.preload(:moderator)
  end

  def get_room_by_slug(slug) when is_binary(slug) do
    Room
    |> Repo.get_by(slug: slug)
    |> Repo.preload(:moderator)
  end

  def create_room(attrs \\ %{}) do
    expires_in = Map.get(attrs, "expires_in", @default_expiry_in)
    attrs = Map.put(attrs, "expires_in", expires_in)

    %Room{}
    |> Room.creation_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, room} ->
        RoomExpiryScheduler.room_created(room)
        broadcast_room_updated(room)
        {:ok, room}

      error ->
        error
    end
  end

  def update_room(%Room{} = room, attrs) do
    room
    |> Room.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_room} ->
        broadcast_room_updated(updated_room)
        {:ok, updated_room}

      error ->
        error
    end
  end

  def delete_room(%Room{} = room) do
    Repo.delete(room)
  end

  def change_room(%Room{} = room, attrs \\ %{}) do
    Room.changeset(room, attrs)
  end

  @doc """
  Deletes every room whose expiry timestamp is at or before now (cascading to
  its questions and votes). Uses `<=` because the expiry scheduler fires its
  timer exactly at the stored (second-precision) expiry boundary. Used by the
  expiry scheduler's housekeeping.
  """
  def cleanup_expired_rooms(now \\ DateTime.utc_now()) do
    Room
    |> where([r], r.expires_at <= ^now)
    |> Repo.all()
    |> then(fn expired_rooms ->
      Enum.each(expired_rooms, fn room ->
        delete_room(room)
        broadcast_room_expired(room)
      end)

      expired_rooms
    end)
  end

  @doc """
  Returns the room with the soonest upcoming expiry, or `nil` when no room
  has a pending expiry. Used to (re)arm the expiry scheduler's timer.
  """
  def next_room_expiry(now \\ DateTime.utc_now()) do
    Room
    |> where([r], r.expires_at > ^now)
    |> order_by([r], asc: r.expires_at)
    |> limit(1)
    |> Repo.one()
  end

  def subscribe_room(room_id) do
    Phoenix.PubSub.subscribe(QaApp.PubSub, "room:#{room_id}")
  end

  @doc """
  Subscribes to announcements about rooms being removed by expiry cleanup.
  """
  def subscribe_rooms do
    Phoenix.PubSub.subscribe(QaApp.PubSub, "rooms")
  end

  def broadcast_room_updated(%Room{} = room) do
    Phoenix.PubSub.broadcast(QaApp.PubSub, "room:#{room.id}", {:room_settings_updated, room})
  end

  defp broadcast_room_expired(%Room{} = room) do
    Phoenix.PubSub.broadcast(QaApp.PubSub, "rooms", {:room_expired, room.id})
  end
end
