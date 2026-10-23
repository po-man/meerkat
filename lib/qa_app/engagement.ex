defmodule QaApp.Engagement do
  @moduledoc """
  The Engagement context for handling questions and votes.
  """

  import Ecto.Query, warn: false
  alias QaApp.Repo
  alias QaApp.Engagement.{Question, Vote}
  alias QaApp.Events.Room

  def list_active_questions(room_id) do
    Question
    |> where([q], q.room_id == ^room_id and q.is_asked == false)
    |> order_by([q], desc: q.vote_count, desc: q.inserted_at)
    |> Repo.all()
  end

  def list_all_questions(room_id) do
    Question
    |> where([q], q.room_id == ^room_id)
    |> order_by([q], desc: q.vote_count, desc: q.inserted_at)
    |> Repo.all()
  end

  def get_question!(id), do: Repo.get!(Question, id)

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
    |> Question.changeset(attrs, room.word_limit)
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
    question
    |> Question.changeset(%{is_asked: true})
    |> Repo.update()
    |> case do
      {:ok, updated_question} ->
        broadcast_question_updated(updated_question)
        {:ok, updated_question}

      error ->
        error
    end
  end

  def toggle_vote(question_id, session_id) do
    question = Repo.get!(Question, question_id)

    # Prevent voting on own question
    if question.session_id == session_id do
      {:error, :cannot_vote_own_question}
    else
      Repo.transaction(fn ->
        case Repo.get_by(Vote, question_id: question_id, session_id: session_id) do
          %Vote{} = existing_vote ->
            Repo.delete!(existing_vote)

            updated_question =
              question
              |> Ecto.Changeset.change(vote_count: max(0, question.vote_count - 1))
              |> Repo.update!()

            broadcast_question_updated(updated_question)
            {:unvoted, updated_question}

          nil ->
            %Vote{}
            |> Vote.changeset(%{question_id: question_id, session_id: session_id})
            |> Repo.insert!()

            updated_question =
              question
              |> Ecto.Changeset.change(vote_count: question.vote_count + 1)
              |> Repo.update!()

            broadcast_question_updated(updated_question)
            {:voted, updated_question}
        end
      end)
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
