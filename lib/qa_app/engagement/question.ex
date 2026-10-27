defmodule QaApp.Engagement.Question do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "engagement_questions" do
    field :session_id, :string
    field :content, :string
    field :vote_count, :integer, default: 0
    field :is_asked, :boolean, default: false

    belongs_to :room, QaApp.Events.Room, foreign_key: :room_id, type: :binary_id
    has_many :votes, QaApp.Engagement.Vote, foreign_key: :question_id

    timestamps(type: :utc_datetime)
  end

  def changeset(question, attrs, char_limit \\ 320) do
    question
    |> cast(attrs, [:room_id, :session_id, :content, :vote_count, :is_asked])
    |> validate_required([:room_id, :session_id, :content])
    |> validate_char_count(:content, char_limit)
    |> unique_constraint([:room_id, :session_id],
      name: :engagement_questions_room_id_session_id_index,
      message: "You have already submitted a question for this event."
    )
  end

  defp validate_char_count(changeset, field, limit) do
    validate_change(changeset, field, fn _, value ->
      count = if is_binary(value), do: String.length(value), else: 0

      if count > limit do
        [
          {field, "exceeds the limit of #{limit} characters (currently #{count} characters)"}
        ]
      else
        []
      end
    end)
  end
end
