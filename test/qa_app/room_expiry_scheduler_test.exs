defmodule QaApp.RoomExpirySchedulerTest do
  use QaApp.DataCase

  alias QaApp.Events.Room
  alias QaApp.RoomExpiryScheduler

  import Ecto.Changeset

  test "boot housekeeping deletes expired rooms and resumes schedules for the rest" do
    past = DateTime.add(DateTime.utc_now(), -60, :second)
    future = DateTime.add(DateTime.utc_now(), 3600, :second)

    expired_room = insert_room!(%{slug: "boot-expired", expires_at: past})
    future_room = insert_room!(%{slug: "boot-future", expires_at: future})

    pid = start_supervised!(RoomExpiryScheduler)

    # Housekeeping removed the expired room...
    refute Repo.get(Room, expired_room.id)

    # ...and the remaining room had its cleanup schedule resumed.
    assert Repo.get(Room, future_room.id)
    assert {_ref, %DateTime{} = armed_at} = :sys.get_state(pid).timer
    assert DateTime.diff(armed_at, future_room.expires_at) |> abs() < 60
  end

  test "force_check cleans expired rooms and re-arms the timer" do
    pid = start_supervised!(RoomExpiryScheduler)

    past = DateTime.add(DateTime.utc_now(), -60, :second)
    future = DateTime.add(DateTime.utc_now(), 3600, :second)

    expired_room = insert_room!(%{slug: "force-expired", expires_at: past})
    future_room = insert_room!(%{slug: "force-future", expires_at: future})

    assert :ok = RoomExpiryScheduler.force_check()

    refute Repo.get(Room, expired_room.id)
    assert Repo.get(Room, future_room.id)

    assert {_ref, %DateTime{} = armed_at} = :sys.get_state(pid).timer
    assert DateTime.diff(armed_at, future_room.expires_at) |> abs() < 60
  end

  test "a room created with an earlier expiry re-arms the timer sooner" do
    pid = start_supervised!(RoomExpiryScheduler)

    later = DateTime.add(DateTime.utc_now(), 7200, :second) |> DateTime.truncate(:second)
    later_room = insert_room!(%{slug: "rearm-later", expires_at: later})

    assert :ok = RoomExpiryScheduler.room_created(later_room)

    assert {_ref, %DateTime{} = armed_at} = :sys.get_state(pid).timer
    assert DateTime.diff(armed_at, later) |> abs() < 60

    sooner = DateTime.add(DateTime.utc_now(), 300, :second) |> DateTime.truncate(:second)
    sooner_room = insert_room!(%{slug: "rearm-sooner", expires_at: sooner})

    assert :ok = RoomExpiryScheduler.room_created(sooner_room)

    assert {_ref, %DateTime{} = rearmed_at} = :sys.get_state(pid).timer
    assert DateTime.diff(rearmed_at, sooner) |> abs() < 60
  end

  test "room_created is a no-op when no scheduler is running" do
    room =
      insert_room!(%{
        slug: "noop-room",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    assert :ok = RoomExpiryScheduler.room_created(room)
    assert :ok = RoomExpiryScheduler.room_created(%Room{})
  end

  test "cleans up a room when its arming timer fires without a restart" do
    start_supervised!(RoomExpiryScheduler)

    expires_at = DateTime.add(DateTime.utc_now(), 1, :second) |> DateTime.truncate(:second)
    room = insert_room!(%{slug: "timer-fire", expires_at: expires_at})

    assert :ok = RoomExpiryScheduler.room_created(room)

    assert wait_until(fn -> Repo.get(Room, room.id) == nil end, 15_000)
  end

  defp wait_until(fun, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    cond do
      fun.() ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(50)
        do_wait_until(fun, deadline)
    end
  end

  defp insert_room!(attrs) do
    attrs = Map.update(attrs, :expires_at, nil, &DateTime.truncate(&1, :second))

    %Room{}
    |> change(attrs)
    |> Repo.insert!()
  end
end
