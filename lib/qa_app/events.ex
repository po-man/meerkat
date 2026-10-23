defmodule QaApp.Events do
  @moduledoc """
  The Events context for managing event rooms.
  """

  import Ecto.Query, warn: false
  alias QaApp.Repo
  alias QaApp.Events.Room

  def list_rooms do
    Room
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
    |> Repo.preload(:admin)
  end

  def get_room!(id) do
    Room
    |> Repo.get!(id)
    |> Repo.preload(:admin)
  end

  def get_room_by_slug(slug) when is_binary(slug) do
    Room
    |> Repo.get_by(slug: slug)
    |> Repo.preload(:admin)
  end

  def create_room(attrs \\ %{}) do
    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, room} ->
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

  def subscribe_room(room_id) do
    Phoenix.PubSub.subscribe(QaApp.PubSub, "room:#{room_id}")
  end

  def broadcast_room_updated(%Room{} = room) do
    Phoenix.PubSub.broadcast(QaApp.PubSub, "room:#{room.id}", {:room_settings_updated, room})
  end
end
