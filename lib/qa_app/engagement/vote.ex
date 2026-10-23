defmodule QaApp.Engagement.Vote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "engagement_votes" do
    field :session_id, :string

    belongs_to :question, QaApp.Engagement.Question, foreign_key: :question_id, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:question_id, :session_id])
    |> validate_required([:question_id, :session_id])
    |> unique_constraint([:question_id, :session_id],
      name: :engagement_votes_question_id_session_id_index,
      message: "You have already voted for this question."
    )
  end
end
