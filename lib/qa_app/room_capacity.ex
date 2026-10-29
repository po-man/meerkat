defmodule QaApp.RoomCapacity do
  @moduledoc """
  Admission and capacity enforcement for room visitors.

  Only live visitors (tracked by `QaApp.Presence`) count toward a room's
  `max_visitors`. This module:

    * gates new visitors (`join/3`) with a race-safe check,
    * expels the newest visitors (`enforce_capacity/1`) when an admin or
      moderator reduces the limit below the current number of visitors.
  """

  import Phoenix.LiveView, only: [connected?: 1]

  alias QaApp.Events.Room
  alias QaApp.Presence

  @doc "The current number of live visitors on the room."
  def count(room_or_id), do: Presence.count(room_or_id)

  @doc "Whether the room is at capacity given the current visitor count."
  def at_capacity?(%Room{max_visitors: nil}, _count), do: false
  def at_capacity?(%Room{max_visitors: limit}, count) when is_integer(limit), do: count >= limit

  @doc """
  Registers the calling LiveView process as a visitor, returning `:ok` when
  admitted or `:full` when the room is at capacity.

  The check is race-safe: when connected it tracks first and, if the resulting
  count is now over the limit (ordering is serialized by the presence tracker),
  it untracks itself and reports `:full`. Two visitors joining concurrently can
  therefore never push the room above its limit.
  """
  def join(socket, %Room{} = room, session_id) do
    room_id = room.id

    if at_capacity?(room, count(room_id)) do
      :full
    else
      join_and_track(socket, room, room_id, session_id)
    end
  end

  defp join_and_track(socket, room, room_id, session_id) do
    if connected?(socket) do
      Presence.track_visitor(room_id, session_id, %{joined_at: System.monotonic_time()})

      if over_limit?(room, count(room_id)) do
        Presence.untrack_visitor(room_id, session_id)
        :full
      else
        :ok
      end
    else
      :ok
    end
  end

  @doc """
  Enforces the room's visitor limit, expelling the newest visitors when the
  current count exceeds `max_visitors` (i.e. after the limit was reduced).

  Each expelled visitor's LiveView receives `{:room_visitors_expelled, ids}`
  on the room's PubSub topic and redirects to the room-full page.
  """
  def enforce_capacity(%Room{max_visitors: nil}), do: :ok

  def enforce_capacity(%Room{} = room) do
    room_id = room.id
    session_ids = Presence.session_ids(room_id)
    excess = length(session_ids) - room.max_visitors

    case pick_excess(session_ids, excess) do
      [] ->
        :ok

      evicted ->
        Phoenix.PubSub.broadcast(
          QaApp.PubSub,
          Presence.topic(room_id),
          {:room_visitors_expelled, evicted}
        )

        :ok
    end
  end

  @doc """
  Picks which visitors to expel when there are `excess` too many.

  Visitors are passed oldest-first (see `Presence.session_ids/1`); the newest
  visitors are removed first so the earliest visitors are kept.
  """
  def pick_excess(_session_ids, excess) when excess <= 0, do: []

  def pick_excess(session_ids, excess) do
    session_ids
    |> Enum.take(-excess)
    |> Enum.reverse()
  end

  defp over_limit?(%Room{max_visitors: nil}, _count), do: false
  defp over_limit?(%Room{max_visitors: limit}, count), do: count > limit
end
