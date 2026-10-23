defmodule QaApp.Events.Room do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "events_rooms" do
    field :slug, :string
    field :title, :string, default: "Live Q&A"
    field :intro_text, :string
    field :word_limit, :integer, default: 50
    field :is_active, :boolean, default: true

    belongs_to :admin, QaApp.Accounts.User, foreign_key: :admin_id, type: :binary_id
    has_many :questions, QaApp.Engagement.Question, foreign_key: :room_id

    timestamps(type: :utc_datetime)
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [:slug, :title, :intro_text, :word_limit, :is_active, :admin_id])
    |> validate_required([:slug, :title, :word_limit, :is_active])
    |> validate_number(:word_limit, greater_than: 0, less_than_or_equal_to: 500)
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> validate_length(:slug, min: 2, max: 100)
    |> unique_constraint(:slug)
  end
end
