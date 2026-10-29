defmodule QaApp.Events.Room do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @expiry_options [
    "3 minutes",
    "30 minutes",
    "1 hour",
    "6 hours",
    "12 hours",
    "1 day",
    "3 days",
    "7 days"
  ]

  @expiry_durations %{
    "3 minutes" => 3,
    "30 minutes" => 30,
    "1 hour" => 60,
    "6 hours" => 6 * 60,
    "12 hours" => 12 * 60,
    "1 day" => 24 * 60,
    "3 days" => 3 * 24 * 60,
    "7 days" => 7 * 24 * 60
  }

  # The default maximum concurrent visitors for a new room. nil is allowed and
  # means "unlimited".
  @default_max_visitors 250

  schema "events_rooms" do
    field :slug, :string
    field :title, :string, default: "Live Q&A"
    field :intro_text, :string
    field :char_limit, :integer, default: 320
    field :max_visitors, :integer, default: @default_max_visitors
    field :is_active, :boolean, default: true
    field :expires_at, :utc_datetime
    field :expires_in, :string, virtual: true

    belongs_to :moderator, QaApp.Accounts.User, foreign_key: :moderator_id, type: :binary_id
    has_many :questions, QaApp.Engagement.Question, foreign_key: :room_id

    timestamps(type: :utc_datetime)
  end

  @doc "The allowed expiry duration labels offered when creating a room."
  def expiry_options, do: @expiry_options

  @doc "The default maximum concurrent visitors used when creating a room."
  def default_max_visitors, do: @default_max_visitors

  @doc """
  Changeset for updating a room. Room expiry is locked at creation time and
  is intentionally not castable here, so it cannot be changed afterwards.
  """
  def changeset(room, attrs) do
    room
    |> cast(normalize_max_visitors(attrs), [
      :slug,
      :title,
      :intro_text,
      :char_limit,
      :max_visitors,
      :is_active,
      :moderator_id
    ])
    |> validate_required([:slug, :title, :char_limit, :is_active])
    |> validate_number(:char_limit, greater_than: 0, less_than_or_equal_to: 1000)
    # nil (empty input) is allowed and means unlimited; otherwise must be >= 1.
    |> validate_number(:max_visitors, greater_than: 0, message: "must be at least 1")
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> validate_length(:slug, min: 2, max: 100)
    |> unique_constraint(:slug)
  end

  # An empty input means "unlimited". Ecto would otherwise silently drop the
  # empty-string change (leaving the struct default), so normalize it to nil.
  defp normalize_max_visitors(%{"max_visitors" => ""} = attrs),
    do: Map.put(attrs, "max_visitors", nil)

  defp normalize_max_visitors(%{max_visitors: ""} = attrs),
    do: Map.put(attrs, :max_visitors, nil)

  defp normalize_max_visitors(attrs), do: attrs

  @doc """
  Changeset used when creating a room. Requires picking one of the allowed
  expiry durations and derives the absolute `expires_at` timestamp from it.
  """
  def creation_changeset(room, attrs) do
    room
    |> changeset(attrs)
    # Force the chosen duration into the changeset so its validation always runs,
    # including when the (defaulted) value equals the struct field's value.
    |> put_change(:expires_in, Map.get(attrs, "expires_in"))
    |> validate_required([:expires_in], message: "must be selected")
    |> validate_inclusion(:expires_in, @expiry_options, message: "is not a valid option")
    |> put_expires_at()
  end

  defp put_expires_at(changeset) do
    case get_change(changeset, :expires_in) do
      label when is_binary(label) ->
        case Map.fetch(@expiry_durations, label) do
          {:ok, minutes} ->
            now = DateTime.utc_now() |> DateTime.truncate(:second)
            put_change(changeset, :expires_at, DateTime.add(now, minutes * 60, :second))

          :error ->
            changeset
        end

      _ ->
        changeset
    end
  end
end
