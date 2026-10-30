defmodule QaApp.Accounts do
  @moduledoc """
  The Accounts context for managing Admins and Moderators.
  """

  import Ecto.Query, warn: false
  alias QaApp.Repo
  alias QaApp.Accounts.User

  def list_users do
    Repo.all(User)
  end

  def list_moderators do
    Repo.all(from u in User, where: u.role == :moderator, order_by: [asc: u.username])
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id) when not is_nil(id), do: Repo.get(User, id)

  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  def create_admin(attrs) do
    attrs_map =
      case attrs do
        %{} -> Map.put(attrs, "role", :admin)
        _ -> %{"role" => :admin}
      end

    %User{}
    |> User.registration_changeset(attrs_map)
    |> Repo.insert()
  end

  def create_moderator(attrs) do
    attrs
    |> change_moderator()
    |> Repo.insert()
  end

  @doc """
  Builds a moderator changeset from the given attributes, applying the role
  and username/password rules shared with `create_moderator/1`. Used to seed
  the "Add Moderator" form and to re-surface validation errors in it.
  """
  def change_moderator(attrs \\ %{}) do
    attrs
    |> Map.put("role", :moderator)
    |> then(&User.registration_changeset(%User{}, &1))
  end

  def update_user_password(%User{} = user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def authenticate_user(username, password) when is_binary(username) and is_binary(password) do
    user = get_user_by_username(username)

    if user && User.verify_password(user, password) do
      {:ok, user}
    else
      {:error, :invalid_credentials}
    end
  end

  def admin_exists? do
    Repo.exists?(from u in User, where: u.role == :admin)
  end
end
