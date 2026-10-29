defmodule QaApp.Presence do
  @moduledoc """
  Tracks live visitors per event room using Phoenix.Presence.

  Only anonymous visitors are tracked, keyed by their `session_id`. Admin and
  moderator sessions are never tracked, so they are never counted as visitors.

  LiveViews already subscribed to a room's PubSub topic (via
  `QaApp.Events.subscribe_room/1`) automatically receive a
  `%Phoenix.Socket.Broadcast{event: "presence_diff", ...}` message whenever the
  visitor presence changes, and can recompute `count/1` from it.
  """

  use Phoenix.Presence,
    otp_app: :qa_app,
    pubsub_server: QaApp.PubSub

  alias QaApp.Events.Room

  @type room_or_id :: Room.t() | String.t()

  @doc "The presence topic used to track visitors of a room."
  def topic(%Room{id: room_id}), do: topic(room_id)
  def topic(room_id) when is_binary(room_id), do: "room:#{room_id}"

  @doc """
  Tracks the calling (LiveView) process as a visitor of the room, keyed by the
  visitor's `session_id`. Must be called from the tracked process itself.
  """
  def track_visitor(room_or_id, session_id, meta \\ %{}) do
    track(self(), topic(room_or_id), session_id, meta)
  end

  @doc "Removes the calling process from the room's presence, if tracked."
  def untrack_visitor(room_or_id, session_id) do
    untrack(self(), topic(room_or_id), session_id)
  end

  @doc "Returns the number of distinct visitors currently present on a room."
  def count(room_or_id) do
    list(topic(room_or_id)) |> map_size()
  end

  @doc """
  Returns the `session_id`s of all visitors on a room, ordered oldest join
  first. A session with several metas (e.g. a browser refresh) uses its
  earliest join time.
  """
  def session_ids(room_or_id) do
    room_or_id
    |> topic()
    |> list()
    |> Enum.map(fn {session_id, meta} -> {session_id, earliest_join(meta.metas)} end)
    |> Enum.sort_by(fn {_session_id, joined_at} -> joined_at end)
    |> Enum.map(fn {session_id, _joined_at} -> session_id end)
  end

  defp earliest_join(metas) do
    Enum.map(metas, & &1.joined_at)
    |> Enum.min(fn -> System.monotonic_time() end)
  end
end
