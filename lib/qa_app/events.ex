defmodule QaApp.Events do
  @moduledoc """
  The Events context for managing event rooms.
  """

  import Ecto.Query, warn: false
  alias QaApp.Repo
  alias QaApp.Events.Room
  alias QaApp.Presence
  alias QaApp.RoomCapacity
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
        # If the limit was reduced below the current visitor count, expel the
        # newest visitors until the room is back at or under capacity.
        RoomCapacity.enforce_capacity(updated_room)
        {:ok, updated_room}

      error ->
        error
    end
  end

  def delete_room(%Room{} = room) do
    case Repo.delete(room) do
      {:ok, _deleted_room} = ok ->
        # The room's votes are gone with it; drop any buffered tally.
        QaApp.Engagement.VoteStore.forget(room.id)
        ok

      error ->
        error
    end
  end

  def change_room(%Room{} = room, attrs \\ %{}) do
    Room.changeset(room, attrs)
  end

  @doc """
  Deletes every room whose expiry timestamp is at or before now (cascading to
  its questions and votes). Uses `<=` to also catch rooms whose expiry landed
  exactly at a (second-precision) boundary; the expiry scheduler arms its
  timer to fire just *after* the boundary so these rooms are always included.
  Used by the expiry scheduler's housekeeping.
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

  @doc "The PubSub topic carrying a room's question feed (questions and votes)."
  def room_topic(%Room{id: room_id}), do: room_topic(room_id)
  def room_topic(room_id) when is_binary(room_id), do: "room:#{room_id}"

  @doc "The PubSub topic carrying a room's settings changes."
  def room_settings_topic(%Room{id: room_id}), do: room_settings_topic(room_id)
  def room_settings_topic(room_id) when is_binary(room_id), do: "room:#{room_id}:settings"

  @doc """
  Subscribes to a room's question feed. Feed events are `{:question_created,
  question}` and `{:question_updated, question}`.
  """
  def subscribe_room(room_or_id) do
    Phoenix.PubSub.subscribe(QaApp.PubSub, room_topic(room_or_id))
  end

  @doc "Subscribes to a room's live visitor presence changes."
  def subscribe_room_presence(room_or_id) do
    Phoenix.PubSub.subscribe(QaApp.PubSub, Presence.topic(room_or_id))
  end

  @doc "Subscribes to a room's settings changes."
  def subscribe_room_settings(room_or_id) do
    Phoenix.PubSub.subscribe(QaApp.PubSub, room_settings_topic(room_or_id))
  end

  @doc """
  Subscribes to announcements about rooms being removed by expiry cleanup.
  """
  def subscribe_rooms do
    Phoenix.PubSub.subscribe(QaApp.PubSub, "rooms")
  end

  def broadcast_room_updated(%Room{} = room) do
    Phoenix.PubSub.broadcast(
      QaApp.PubSub,
      room_settings_topic(room),
      {:room_settings_updated, room}
    )

    # Also announce on the global rooms topic so open room listings (admin
    # control center and moderator dashboard) refresh their rows live when the
    # settings change from another view (e.g. a status toggle).
    Phoenix.PubSub.broadcast(QaApp.PubSub, "rooms", {:rooms_settings_updated, room})
  end

  defp broadcast_room_expired(%Room{} = room) do
    Phoenix.PubSub.broadcast(QaApp.PubSub, "rooms", {:room_expired, room.id})
  end
end
