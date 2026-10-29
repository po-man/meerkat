defmodule QaApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "accounts_users" do
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :role, Ecto.Enum, values: [:admin, :moderator]

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :role])
    |> validate_required([:username, :role])
    |> validate_length(:username, min: 3, max: 50)
    |> unique_constraint(:username)
  end

  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 6, max: 72)
    |> hash_password()
  end

  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 6, max: 72)
    |> hash_password()
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      password when is_binary(password) ->
        put_change(changeset, :hashed_password, Pbkdf2.hash_pwd_salt(password))

      _ ->
        changeset
    end
  end

  def verify_password(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(password) and is_binary(hashed_password) do
    Pbkdf2.verify_pass(password, hashed_password)
  end

  def verify_password(_user, _password), do: Pbkdf2.no_user_verify()
end
