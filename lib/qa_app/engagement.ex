defmodule QaApp.Engagement do
  @moduledoc """
  The Engagement context for handling questions and votes.
  """

  import Ecto.Query, warn: false
  alias QaApp.Repo
  alias QaApp.Engagement.{Question, Vote, VoteStore}
  alias QaApp.Events
  alias QaApp.Events.Room

  def list_active_questions(room_id) do
    flush_votes(room_id)
    list_questions_by_asked(room_id, false)
  end

  def list_asked_questions(room_id) do
    flush_votes(room_id)
    list_questions_by_asked(room_id, true)
  end

  def list_all_questions(room_id) do
    flush_votes(room_id)

    Question
    |> where([q], q.room_id == ^room_id)
    |> order_by([q], desc: q.vote_count, desc: q.inserted_at)
    |> Repo.all()
  end

  defp list_questions_by_asked(room_id, is_asked) do
    Question
    |> where([q], q.room_id == ^room_id and q.is_asked == ^is_asked)
    |> order_by([q], desc: q.vote_count, desc: q.inserted_at)
    |> Repo.all()
  end

  def get_question_by_session(room_id, session_id) do
    flush_votes(room_id)

    Question
    |> Repo.get_by(room_id: room_id, session_id: session_id)
  end

  def change_question(%Room{} = room, session_id, attrs \\ %{}) do
    %Question{room_id: room.id, session_id: session_id}
    |> Question.changeset(attrs, room.char_limit)
  end

  def create_question(%Room{} = room, session_id, attrs) do
    attrs =
      attrs
      |> Map.put("room_id", room.id)
      |> Map.put("session_id", session_id)

    %Question{}
    |> Question.changeset(attrs, room.char_limit)
    |> Repo.insert()
    |> case do
      {:ok, question} ->
        VoteStore.put_question(room.id, question)
        broadcast_question_created(question)
        {:ok, question}

      error ->
        error
    end
  end

  def mark_as_asked(%Question{} = question) do
    update_asked_state(question, true)
  end

  def mark_as_unasked(%Question{} = question) do
    update_asked_state(question, false)
  end

  @doc """
  Marks a question in `room_id` as asked/unasked. Returns `{:error,
  :question_not_found}` when the question does not belong to that room, so
  moderators can never touch questions outside their own room.
  """
  def set_question_asked(room_id, question_id, is_asked) when is_boolean(is_asked) do
    case Repo.get_by(Question, id: question_id, room_id: room_id) do
      nil -> {:error, :question_not_found}
      question -> update_asked_state(question, is_asked)
    end
  end

  defp update_asked_state(%Question{} = question, is_asked) do
    question
    |> Question.changeset(%{is_asked: is_asked})
    |> Repo.update()
    |> case do
      {:ok, updated_question} ->
        VoteStore.put_question(updated_question.room_id, updated_question)
        broadcast_question_updated(updated_question)
        {:ok, updated_question}

      error ->
        error
    end
  end

  @doc """
  Toggles a visitor's vote on a question.

  Votes are applied in memory by `QaApp.Engagement.VoteStore` and persisted in
  batches, so a click never waits on SQLite's single write lock.
  """
  def toggle_vote(room_id, question_id, session_id) do
    VoteStore.toggle(room_id, question_id, session_id)
  end

  @doc """
  Returns the ids of the questions `session_id` has voted on in the room.

  Pending in-memory votes win over the database, so a visitor who toggles a
  vote and immediately refreshes still sees the correct button state.
  """
  def list_user_voted_question_ids(room_id, session_id) do
    case VoteStore.user_voted_ids(room_id, session_id) do
      {:ok, ids} -> ids
      :error -> load_user_voted_question_ids(room_id, session_id)
    end
  end

  defp load_user_voted_question_ids(room_id, session_id) do
    Vote
    |> join(:inner, [v], q in assoc(v, :question))
    |> where([v, q], q.room_id == ^room_id and v.session_id == ^session_id)
    |> select([v], v.question_id)
    |> Repo.all()
    |> MapSet.new()
  end

  def broadcast_question_created(%Question{} = question) do
    Phoenix.PubSub.broadcast(
      QaApp.PubSub,
      Events.room_topic(question.room_id),
      {:question_created, question}
    )
  end

  def broadcast_question_updated(%Question{} = question) do
    Phoenix.PubSub.broadcast(
      QaApp.PubSub,
      Events.room_topic(question.room_id),
      {:question_updated, question}
    )
  end

  # Reads must not observe stale vote counts while deltas are still buffered.
  # Flushing is a no-op once the room is clean, so this is cheap.
  defp flush_votes(room_id), do: VoteStore.flush(room_id)
end
