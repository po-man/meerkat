defmodule QaApp.RoomCapacityTest do
  use QaApp.DataCase

  alias QaApp.Events
  alias QaApp.Events.Room
  alias QaApp.Presence
  alias QaApp.RoomCapacity

  describe "pick_excess/2" do
    test "returns no one when there is no excess" do
      assert RoomCapacity.pick_excess(["a", "b", "c"], 0) == []
    end

    test "returns no one for a negative excess" do
      assert RoomCapacity.pick_excess(["a", "b", "c"], -2) == []
    end

    test "picks the newest visitors first (input is oldest-first)" do
      assert RoomCapacity.pick_excess(["a", "b", "c", "d"], 2) == ["d", "c"]
    end

    test "picks everyone when the excess equals the count" do
      assert RoomCapacity.pick_excess(["a", "b"], 2) == ["b", "a"]
    end
  end

  describe "at_capacity?/2" do
    test "is never at capacity for unlimited rooms" do
      assert RoomCapacity.at_capacity?(%Room{max_visitors: nil}, 99_999) == false
    end

    test "reaches capacity at the configured limit" do
      room = %Room{max_visitors: 5}

      refute RoomCapacity.at_capacity?(room, 4)
      assert RoomCapacity.at_capacity?(room, 5)
      assert RoomCapacity.at_capacity?(room, 6)
    end
  end

  describe "enforce_capacity/1" do
    test "expels the newest visitors when the limit is reduced below the current count" do
      {:ok, room} = create_room("cap-room", 250)

      track_visitor(room, "v-1", 2)
      track_visitor(room, "v-2", 3)
      track_visitor(room, "v-3", 4)

      assert Presence.session_ids(room.id) == ["v-1", "v-2", "v-3"]

      Phoenix.PubSub.subscribe(QaApp.PubSub, Presence.topic(room))

      assert {:ok, updated_room} = Events.update_room(room, %{"max_visitors" => "2"})
      assert updated_room.max_visitors == 2

      # Only the two earliest visitors (v-1, v-2) get to stay; v-3 is expelled.
      assert_receive {:room_visitors_expelled, ["v-3"]}
      refute_received {:room_visitors_expelled, ["v-2"]}

      # The expelled visitor's LiveView untracks as it leaves, but the presence
      # entry itself is only removed by the client going away (assert count
      # here documents that enforce_capacity alone does not untrack).
      assert Presence.count(room.id) == 3
    end

    test "does not expel anyone when the room is not over its limit" do
      {:ok, room} = create_room("cap-room-limit", 250)

      track_visitor(room, "single", 1)

      Phoenix.PubSub.subscribe(QaApp.PubSub, Presence.topic(room))

      assert {:ok, updated_room} = Events.update_room(room, %{"max_visitors" => "1"})
      assert updated_room.max_visitors == 1

      refute_received {:room_visitors_expelled, _}
    end

    test "does not expel when the limit is unlimited" do
      {:ok, room} = create_room("cap-room-unlimited", nil)

      track_visitor(room, "single", 1)

      Phoenix.PubSub.subscribe(QaApp.PubSub, Presence.topic(room))

      assert {:ok, updated_room} = Events.update_room(room, %{"max_visitors" => ""})
      assert is_nil(updated_room.max_visitors)

      refute_received {:room_visitors_expelled, _}
    end
  end

  describe "presence diffs" do
    test "subscribers to the room topic receive presence_diff broadcasts", %{} do
      {:ok, room} = create_room("diff-room", 100)

      Phoenix.PubSub.subscribe(QaApp.PubSub, Presence.topic(room))
      track_visitor(room, "diffy", 1)

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "presence_diff",
                       topic: "room:" <> room_id
                     },
                     1000

      assert room_id == room.id
    end
  end

  defp create_room(slug, max_visitors) do
    Events.create_room(%{
      "slug" => slug,
      "title" => "Capacity Room",
      "is_active" => true,
      "expires_in" => "1 hour",
      "max_visitors" => max_visitors
    })
  end

  defp track_visitor(room, session_id, joined_at) do
    start_supervised!(
      {Task,
       fn ->
         Presence.track_visitor(room.id, session_id, %{joined_at: joined_at})
         receive do: (:stop -> :ok)
       end},
      id: {:visitor, room.id, session_id}
    )

    # Block until the presence tracker has processed the (async) track cast.
    :sys.get_state(QaApp.Presence)
    :ok
  end
end
