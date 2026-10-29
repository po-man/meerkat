defmodule QaApp.Engagement do
  @moduledoc """
  The Engagement context for handling questions and votes.
  """

  import Ecto.Query, warn: false
  alias QaApp.Repo
  alias QaApp.Engagement.{Question, Vote}
  alias QaApp.Events.Room

  def list_active_questions(room_id) do
    list_questions_by_asked(room_id, false)
  end

  def list_asked_questions(room_id) do
    list_questions_by_asked(room_id, true)
  end

  def list_all_questions(room_id) do
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
    Question
    |> Repo.get_by(room_id: room_id, session_id: session_id)
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
        broadcast_question_updated(updated_question)
        {:ok, updated_question}

      error ->
        error
    end
  end

  def toggle_vote(room_id, question_id, session_id) do
    question = Repo.get!(Question, question_id)

    cond do
      question.room_id != room_id ->
        # Never allow voting on a question from another room.
        {:error, :invalid_room}

      question.session_id == session_id ->
        {:error, :cannot_vote_own_question}

      true ->
        case Repo.transaction(fn ->
               do_toggle_vote(question, question_id, session_id)
             end) do
          {:ok, {direction, updated_question}} ->
            broadcast_question_updated(updated_question)
            {:ok, {direction, updated_question}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp do_toggle_vote(question, question_id, session_id) do
    case Repo.get_by(Vote, question_id: question_id, session_id: session_id) do
      %Vote{} = existing_vote ->
        Repo.delete!(existing_vote)

        updated_question =
          question
          |> Ecto.Changeset.change(vote_count: max(0, question.vote_count - 1))
          |> Repo.update!()

        {:unvoted, updated_question}

      nil ->
        %Vote{}
        |> Vote.changeset(%{question_id: question_id, session_id: session_id})
        |> Repo.insert!()

        updated_question =
          question
          |> Ecto.Changeset.change(vote_count: question.vote_count + 1)
          |> Repo.update!()

        {:voted, updated_question}
    end
  end

  def list_user_voted_question_ids(room_id, session_id) do
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
      "room:#{question.room_id}",
      {:question_created, question}
    )
  end

  def broadcast_question_updated(%Question{} = question) do
    Phoenix.PubSub.broadcast(
      QaApp.PubSub,
      "room:#{question.room_id}",
      {:question_updated, question}
    )
  end
end
