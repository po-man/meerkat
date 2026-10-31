defmodule QaApp.Engagement.VoteStore do
  @moduledoc """
  In-memory, per-room vote tally with batched persistence.

  SQLite allows a single writer. Writing one transaction per click therefore
  serializes every vote, and during a burst all pooled connections end up
  parked inside SQLite's write-lock wait until the pool can no longer serve
  requests at all.

  This process applies votes to its own state instead (a map update measured
  in microseconds) and flushes the accumulated deltas in a single transaction
  per room, either on a timer or when a reader asks for fresh data.

  The database stays the source of truth for cold reads: `flush/1` persists
  any pending deltas first, so queries never observe stale vote counts. A
  clean room makes `flush/1` a no-op.

  The store is deliberately a single process: every live event has one hot
  room, and each operation is trivial. If that ever changes, shard by
  `room_id`.
  """

  use GenServer

  require Logger

  import Ecto.Query, only: [from: 2]

  alias QaApp.Engagement.{Question, Vote}
  alias QaApp.Events
  alias QaApp.Repo

  @default_flush_interval 1_000
  @default_broadcast_interval 150
  @call_timeout 5_000

  # Client

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Toggles `session_id`'s vote on a question, entirely in memory.

  Returns the same contract as before the store existed, so callers do not
  need to know whether votes are persisted yet.
  """
  def toggle(room_id, question_id, session_id) do
    GenServer.call(__MODULE__, {:toggle, room_id, question_id, session_id}, @call_timeout)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @doc """
  Returns the question ids `session_id` has voted on, or `:error` when the
  room is not loaded in memory (in which case the database is authoritative,
  because an unloaded room cannot have pending votes).
  """
  def user_voted_ids(room_id, session_id) do
    GenServer.call(__MODULE__, {:user_voted_ids, room_id, session_id}, @call_timeout)
  catch
    :exit, _ -> :error
  end

  @doc "Persists pending vote deltas for the room. No-op when nothing is dirty."
  def flush(room_id) do
    GenServer.call(__MODULE__, {:flush, room_id}, @call_timeout)
  catch
    :exit, _ -> :ok
  end

  @doc """
  Keeps the cache in sync after a question is created or updated. The vote
  count already held in memory wins, since it may be ahead of the database.
  """
  def put_question(room_id, %Question{} = question) do
    GenServer.call(__MODULE__, {:put_question, room_id, question}, @call_timeout)
  catch
    :exit, _ -> :ok
  end

  @doc "Drops a room's state without flushing (the room is being deleted)."
  def forget(room_id) do
    GenServer.call(__MODULE__, {:forget, room_id}, @call_timeout)
  catch
    :exit, _ -> :ok
  end

  @doc "Clears all in-memory state. Used between tests."
  def reset! do
    if Process.whereis(__MODULE__), do: GenServer.call(__MODULE__, :reset, @call_timeout)
  end

  # Server

  @impl true
  def init(opts) do
    # Required so `terminate/2` can flush pending votes on a graceful shutdown.
    Process.flag(:trap_exit, true)

    config = Keyword.merge(Application.get_env(:qa_app, __MODULE__, []), opts)

    {:ok,
     %{
       rooms: %{},
       flush_interval: Keyword.get(config, :flush_interval, @default_flush_interval),
       broadcast_interval: Keyword.get(config, :broadcast_interval, @default_broadcast_interval)
     }}
  end

  @impl true
  def handle_call({:toggle, room_id, question_id, session_id}, _from, state) do
    case fetch_room(state, room_id) do
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      {:ok, room, state} ->
        case Map.fetch(room.questions, question_id) do
          :error ->
            {:reply, missing_question_error(question_id), state}

          {:ok, question} ->
            if question.session_id == session_id do
              {:reply, {:error, :cannot_vote_own_question}, state}
            else
              {room, question, direction} = apply_toggle(room, question, session_id, state)
              {:reply, {:ok, {direction, question}}, store_room(state, room)}
            end
        end
    end
  end

  def handle_call({:user_voted_ids, room_id, session_id}, _from, state) do
    case Map.fetch(state.rooms, room_id) do
      {:ok, room} ->
        {:reply, {:ok, Map.get(room.voters, session_id, MapSet.new())}, state}

      :error ->
        {:reply, :error, state}
    end
  end

  def handle_call({:flush, room_id}, _from, state) do
    {:reply, :ok, flush_room(state, room_id)}
  end

  def handle_call({:put_question, room_id, %Question{} = question}, _from, state) do
    state =
      case Map.fetch(state.rooms, room_id) do
        {:ok, room} ->
          # Preserve the in-memory count: it may be ahead of the database.
          cached = Map.get(room.questions, question.id)
          question = if cached, do: %{question | vote_count: cached.vote_count}, else: question

          store_room(state, %{
            room
            | questions: Map.put(room.questions, question.id, question)
          })

        :error ->
          state
      end

    {:reply, :ok, state}
  end

  def handle_call({:forget, room_id}, _from, state) do
    case Map.fetch(state.rooms, room_id) do
      {:ok, room} ->
        cancel_timers(room)
        {:reply, :ok, %{state | rooms: Map.delete(state.rooms, room_id)}}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call(:reset, _from, state) do
    Enum.each(state.rooms, fn {_room_id, room} -> cancel_timers(room) end)
    {:reply, :ok, %{state | rooms: %{}}}
  end

  @impl true
  def handle_info({:flush, room_id}, state) do
    state = put_room_field(state, room_id, :flush_timer, nil)
    {:noreply, flush_room(state, room_id)}
  end

  def handle_info({:broadcast, room_id}, state) do
    state = put_room_field(state, room_id, :broadcast_timer, nil)
    {:noreply, broadcast_room(state, room_id)}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.rooms, fn {_room_id, room} -> flush_room(state, room.id) end)
    :ok
  end

  # Toggle

  defp apply_toggle(room, question, session_id, state) do
    key = {question.id, session_id}
    voted? = MapSet.member?(Map.get(room.voters, session_id, MapSet.new()), question.id)

    if voted? do
      question = %{question | vote_count: max(0, question.vote_count - 1), updated_at: now()}

      {pending_adds, pending_removes} =
        if MapSet.member?(room.pending_adds, key) do
          # The vote never reached the database, so there is nothing to undo.
          {MapSet.delete(room.pending_adds, key), room.pending_removes}
        else
          {room.pending_adds, MapSet.put(room.pending_removes, key)}
        end

      room = %{
        room
        | questions: Map.put(room.questions, question.id, question),
          voters: remove_vote(room.voters, session_id, question.id),
          pending_adds: pending_adds,
          pending_removes: pending_removes,
          dirty: MapSet.put(room.dirty, question.id),
          broadcast_pending: MapSet.put(room.broadcast_pending, question.id)
      }

      {schedule(room, state), question, :unvoted}
    else
      question = %{question | vote_count: question.vote_count + 1, updated_at: now()}

      {pending_adds, pending_removes} =
        if MapSet.member?(room.pending_removes, key) do
          # Re-voted before the removal was flushed; the row still exists.
          {room.pending_adds, MapSet.delete(room.pending_removes, key)}
        else
          {MapSet.put(room.pending_adds, key), room.pending_removes}
        end

      room = %{
        room
        | questions: Map.put(room.questions, question.id, question),
          voters: add_vote(room.voters, session_id, question.id),
          pending_adds: pending_adds,
          pending_removes: pending_removes,
          dirty: MapSet.put(room.dirty, question.id),
          broadcast_pending: MapSet.put(room.broadcast_pending, question.id)
      }

      {schedule(room, state), question, :voted}
    end
  end

  defp add_vote(voters, session_id, question_id) do
    Map.update(voters, session_id, MapSet.new([question_id]), &MapSet.put(&1, question_id))
  end

  defp remove_vote(voters, session_id, question_id) do
    case Map.fetch(voters, session_id) do
      :error ->
        voters

      {:ok, ids} ->
        ids = MapSet.delete(ids, question_id)

        if MapSet.size(ids) == 0 do
          Map.delete(voters, session_id)
        else
          Map.put(voters, session_id, ids)
        end
    end
  end

  # The question is not cached for this room: either it does not exist, or it
  # belongs to a different room. Both are rare, so a database lookup is fine.
  defp missing_question_error(question_id) do
    try do
      case Repo.get(Question, question_id) do
        nil -> {:error, :question_not_found}
        _question -> {:error, :invalid_room}
      end
    rescue
      _exception -> {:error, :unavailable}
    end
  end

  # Timers

  defp schedule(room, state) do
    room
    |> ensure_timer(:flush_timer, {:flush, room.id}, state.flush_interval)
    |> ensure_timer(:broadcast_timer, {:broadcast, room.id}, state.broadcast_interval)
  end

  defp ensure_timer(room, field, message, interval) do
    if Map.fetch!(room, field) do
      room
    else
      Map.put(room, field, Process.send_after(self(), message, interval))
    end
  end

  defp cancel_timers(room) do
    if room.flush_timer, do: Process.cancel_timer(room.flush_timer)
    if room.broadcast_timer, do: Process.cancel_timer(room.broadcast_timer)
    :ok
  end

  # Persistence

  defp flush_room(state, room_id) do
    case Map.fetch(state.rooms, room_id) do
      :error ->
        state

      {:ok, room} ->
        if dirty?(room) do
          case persist(room) do
            :ok ->
              if room.flush_timer, do: Process.cancel_timer(room.flush_timer)

              store_room(state, %{
                room
                | flush_timer: nil,
                  dirty: MapSet.new(),
                  pending_adds: MapSet.new(),
                  pending_removes: MapSet.new()
              })

            {:error, reason} ->
              # Keep the deltas in memory and retry on the next flush.
              Logger.error("VoteStore failed to flush room #{room_id}: #{inspect(reason)}")

              room
              |> Map.put(:flush_timer, nil)
              |> ensure_timer(:flush_timer, {:flush, room_id}, state.flush_interval)
              |> then(&store_room(state, &1))
          end
        else
          state
        end
    end
  end

  defp dirty?(room) do
    MapSet.size(room.dirty) > 0 or MapSet.size(room.pending_adds) > 0 or
      MapSet.size(room.pending_removes) > 0
  end

  defp persist(room) do
    now = now()

    try do
      Repo.transaction(
        fn ->
          rows =
            Enum.map(room.pending_adds, fn {question_id, session_id} ->
              %{
                id: Ecto.UUID.generate(),
                question_id: question_id,
                session_id: session_id,
                inserted_at: now,
                updated_at: now
              }
            end)

          if rows != [] do
            Repo.insert_all(Vote, rows, on_conflict: :nothing)
          end

          Enum.each(room.pending_removes, fn {question_id, session_id} ->
            Repo.delete_all(
              from v in Vote,
                where: v.question_id == ^question_id and v.session_id == ^session_id
            )
          end)

          Enum.each(room.dirty, fn question_id ->
            question = Map.fetch!(room.questions, question_id)

            Repo.update_all(
              from(q in Question, where: q.id == ^question_id),
              set: [vote_count: question.vote_count, updated_at: now]
            )
          end)
        end,
        mode: :immediate
      )
      |> case do
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, reason}
      end
    rescue
      exception -> {:error, exception}
    end
  end

  # Broadcasts

  defp broadcast_room(state, room_id) do
    case Map.fetch(state.rooms, room_id) do
      :error ->
        state

      {:ok, room} ->
        questions =
          room.broadcast_pending
          |> Enum.map(&Map.fetch!(room.questions, &1))

        if questions != [] do
          Phoenix.PubSub.broadcast(
            QaApp.PubSub,
            Events.room_topic(room_id),
            {:questions_updated, questions}
          )
        end

        store_room(state, %{room | broadcast_pending: MapSet.new()})
    end
  end

  # State helpers

  defp fetch_room(state, room_id) do
    case Map.fetch(state.rooms, room_id) do
      {:ok, room} ->
        {:ok, room, state}

      :error ->
        case load_room(room_id) do
          {:ok, room} -> {:ok, room, store_room(state, room)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp load_room(room_id) do
    try do
      questions =
        Repo.all(
          from q in Question,
            where: q.room_id == ^room_id
        )

      votes =
        Repo.all(
          from v in Vote,
            join: q in assoc(v, :question),
            where: q.room_id == ^room_id,
            select: {v.question_id, v.session_id}
        )

      voters =
        Enum.reduce(votes, %{}, fn {question_id, session_id}, acc ->
          add_vote(acc, session_id, question_id)
        end)

      {:ok,
       %{
         id: room_id,
         questions: Map.new(questions, &{&1.id, &1}),
         voters: voters,
         dirty: MapSet.new(),
         pending_adds: MapSet.new(),
         pending_removes: MapSet.new(),
         broadcast_pending: MapSet.new(),
         flush_timer: nil,
         broadcast_timer: nil
       }}
    rescue
      exception -> {:error, exception}
    end
  end

  defp store_room(state, room) do
    %{state | rooms: Map.put(state.rooms, room.id, room)}
  end

  defp put_room_field(state, room_id, field, value) do
    case Map.fetch(state.rooms, room_id) do
      {:ok, room} -> store_room(state, Map.put(room, field, value))
      :error -> state
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
