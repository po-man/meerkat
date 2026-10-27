defmodule QaApp.RoomExpiryScheduler do
  @moduledoc """
  Schedules cleanup of expired event rooms.

  On boot it runs a housekeeping pass that deletes any already-expired rooms and
  then resumes the cleanup schedule for the remaining rooms. After that it keeps
  a single timer armed for the room with the soonest upcoming expiry; whenever
  that timer fires it cleans up affected rooms and re-arms for the next one.
  """

  use GenServer

  alias QaApp.Events

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Notifies the scheduler that a room was created so its expiry schedule can be
  taken into account. Safe to call when the scheduler is not running, in which
  case it is a no-op.
  """
  def room_created(%QaApp.Events.Room{expires_at: expires_at}) when not is_nil(expires_at) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:room_created, expires_at})
    end

    :ok
  end

  def room_created(_room), do: :ok

  @doc """
  Immediately runs a cleanup pass and re-arms the timer. Mainly used by tests.
  """
  def force_check do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :force_check)
    else
      :ok
    end
  end

  @impl true
  def init(_opts) do
    # Server kickstarted: housekeeping first, then resume remaining schedules.
    Events.cleanup_expired_rooms()
    {:ok, arm(%{timer: nil})}
  end

  @impl true
  def handle_info(:expiry_check, state) do
    Events.cleanup_expired_rooms()
    {:noreply, arm(state)}
  end

  @impl true
  def handle_cast({:room_created, expires_at}, state) do
    state =
      case state.timer do
        nil ->
          # No schedule running yet; resume one for the newly created room.
          arm(state)

        {_ref, armed_at} ->
          if DateTime.compare(expires_at, armed_at) == :lt do
            arm(state)
          else
            state
          end
      end

    {:noreply, state}
  end

  @impl true
  def handle_call(:force_check, _from, state) do
    Events.cleanup_expired_rooms()
    {:reply, :ok, arm(state)}
  end

  defp arm(state) do
    case Events.next_room_expiry() do
      nil ->
        cancel_timer(state.timer)
        %{state | timer: nil}

      %QaApp.Events.Room{expires_at: expires_at} ->
        cancel_timer(state.timer)

        delay =
          max(DateTime.diff(expires_at, DateTime.utc_now(), :millisecond), 0)

        ref = Process.send_after(self(), :expiry_check, delay)
        %{state | timer: {ref, expires_at}}
    end
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer({ref, _expires_at}), do: Process.cancel_timer(ref)
end
