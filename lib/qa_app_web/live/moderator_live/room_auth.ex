defmodule QaAppWeb.ModeratorLive.RoomAuth do
  @moduledoc """
  Shared room loading and authorization for moderator room pages.

  Used by `QaAppWeb.ModeratorLive.Show` and `QaAppWeb.ModeratorLive.Settings`
  so both pages follow the same flow: load the room by slug, verify the
  current user is an admin or the assigned moderator, and assign `:room`.

  Subscription is intentionally left to each LiveView: the questions page needs
  the feed and settings topics, while the settings page only needs settings and
  presence. Subscribing both to the feed topic made every vote crash the
  settings page.

  Returns `{:ok, socket}` when authorized or `{:redirect, socket}` with a
  flash message and a redirect otherwise.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias QaApp.Events

  def authorize(socket, %{"slug" => slug}) do
    case Events.get_room_by_slug(slug) do
      nil ->
        {:redirect,
         socket
         |> put_flash(:error, "Event room not found")
         |> redirect(to: "/")}

      room ->
        current_user = socket.assigns[:current_user]

        if current_user && (current_user.role == :admin || current_user.id == room.moderator_id) do
          {:ok, assign(socket, :room, room)}
        else
          {:redirect,
           socket
           |> put_flash(:error, "Unauthorized access to this room dashboard.")
           |> redirect(to: "/")}
        end
    end
  end
end
