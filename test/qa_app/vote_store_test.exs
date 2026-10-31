defmodule QaApp.Engagement.VoteStoreTest do
  use QaApp.DataCase, async: false

  alias QaApp.Engagement
  alias QaApp.Engagement.{Question, Vote, VoteStore}
  alias QaApp.Events

  setup do
    {:ok, room} =
      Events.create_room(%{
        "slug" => "store-room",
        "title" => "Store Room",
        "char_limit" => 320,
        "is_active" => true,
        "expires_in" => "1 hour"
      })

    {:ok, other_room} =
      Events.create_room(%{
        "slug" => "store-other-room",
        "title" => "Other Room",
        "char_limit" => 320,
        "is_active" => true,
        "expires_in" => "1 hour"
      })

    {:ok, question} = Engagement.create_question(room, "author", %{"content" => "Vote on me"})

    {:ok, _other_question} =
      Engagement.create_question(other_room, "other-author", %{"content" => "Elsewhere"})

    {:ok, room: room, other_room: other_room, question: question}
  end

  describe "toggle/3" do
    test "toggles a vote in memory", %{room: room, question: question} do
      assert {:ok, {:voted, voted}} = Engagement.toggle_vote(room.id, question.id, "voter")
      assert voted.vote_count == 1

      assert {:ok, {:unvoted, unvoted}} =
               Engagement.toggle_vote(room.id, question.id, "voter")

      assert unvoted.vote_count == 0
    end

    test "keeps one vote per session", %{room: room, question: question} do
      assert {:ok, {:voted, _}} = Engagement.toggle_vote(room.id, question.id, "voter")
      assert {:ok, {:unvoted, _}} = Engagement.toggle_vote(room.id, question.id, "voter")
      assert {:ok, {:voted, voted}} = Engagement.toggle_vote(room.id, question.id, "voter")

      assert voted.vote_count == 1
    end

    test "rejects voting your own question", %{room: room, question: question} do
      assert {:error, :cannot_vote_own_question} =
               Engagement.toggle_vote(room.id, question.id, "author")
    end

    test "rejects voting on a question from another room", %{
      other_room: other_room,
      question: question
    } do
      assert {:error, :invalid_room} = Engagement.toggle_vote(other_room.id, question.id, "voter")
    end

    test "rejects unknown questions", %{room: room} do
      assert {:error, :question_not_found} =
               Engagement.toggle_vote(room.id, Ecto.UUID.generate(), "voter")
    end
  end

  describe "flush/1" do
    test "persists counts and vote rows", %{room: room, question: question} do
      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter-a")
      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter-b")

      # Nothing is written until the store is asked to flush.
      assert Repo.get!(Question, question.id).vote_count == 0
      assert Repo.aggregate(Vote, :count) == 0

      assert :ok = VoteStore.flush(room.id)

      assert Repo.get!(Question, question.id).vote_count == 2
      assert Repo.aggregate(Vote, :count) == 2
    end

    test "drops a vote that was toggled back before flushing", %{room: room, question: question} do
      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter")
      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter")

      assert :ok = VoteStore.flush(room.id)

      assert Repo.get!(Question, question.id).vote_count == 0
      assert Repo.aggregate(Vote, :count) == 0
    end

    test "removes a previously persisted vote", %{room: room, question: question} do
      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter")
      :ok = VoteStore.flush(room.id)

      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter")
      :ok = VoteStore.flush(room.id)

      assert Repo.get!(Question, question.id).vote_count == 0
      assert Repo.aggregate(Vote, :count) == 0
    end

    test "is a no-op for a clean room", %{room: room, question: question} do
      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter")
      :ok = VoteStore.flush(room.id)

      assert :ok = VoteStore.flush(room.id)
      assert Repo.get!(Question, question.id).vote_count == 1
    end
  end

  describe "reads" do
    test "flush pending votes before returning", %{room: room, question: question} do
      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter")

      assert [%Question{vote_count: 1}] = Engagement.list_active_questions(room.id)
      assert Engagement.get_question_by_session(room.id, "author").vote_count == 1
    end

    test "report pending votes for a session", %{room: room, question: question} do
      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter")

      assert Engagement.list_user_voted_question_ids(room.id, "voter") ==
               MapSet.new([question.id])

      assert Engagement.list_user_voted_question_ids(room.id, "someone-else") == MapSet.new()
    end

    test "reload persisted votes after a reset", %{room: room, question: question} do
      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter")
      :ok = VoteStore.flush(room.id)

      VoteStore.reset!()

      assert [%Question{vote_count: 1}] = Engagement.list_active_questions(room.id)

      assert Engagement.list_user_voted_question_ids(room.id, "voter") ==
               MapSet.new([question.id])
    end
  end

  describe "question cache" do
    test "a question created after the room is loaded can be voted on", %{
      room: room,
      question: question
    } do
      # Loads the room into the store.
      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter")

      {:ok, new_question} =
        Engagement.create_question(room, "new-author", %{"content" => "New question"})

      assert {:ok, {:voted, voted}} =
               Engagement.toggle_vote(room.id, new_question.id, "another-voter")

      assert voted.vote_count == 1
    end

    test "marking a question asked keeps its in-memory count", %{
      room: room,
      question: question
    } do
      {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter")
      {:ok, _} = Engagement.mark_as_asked(question)

      assert [%Question{vote_count: 1, is_asked: true}] = Engagement.list_asked_questions(room.id)
      assert Engagement.list_active_questions(room.id) == []
    end
  end

  test "forgetting a room drops its buffered votes", %{room: room, question: question} do
    {:ok, _} = Engagement.toggle_vote(room.id, question.id, "voter")
    :ok = VoteStore.forget(room.id)

    assert Repo.get!(Question, question.id).vote_count == 0
    assert Repo.aggregate(Vote, :count) == 0
  end
end
