defmodule QaAppWeb.ModeratorLive.Dashboard do
  use QaAppWeb, :live_view

  alias QaApp.Events

  # How long an armed "deactivate room" confirmation stays open before it
  # auto-cancels, protecting against an accidental close.
  @deactivate_confirm_timeout 6_000

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Events.subscribe_rooms()
    end

    {:ok,
     socket
     |> assign(:confirm_deactivate_id, nil)
     |> assign(:confirm_deactivate_room, nil)
     |> stream_rooms()}
  end

  def handle_info({:room_expired, _room_id}, socket) do
    {:noreply, stream_rooms(socket)}
  end

  # A room's settings changed from another view (admin control center or the
  # room settings tab). Refresh the rows so the status toggle stays live, and
  # clear any armed deactivation confirmation.
  def handle_info({:rooms_settings_updated, _room}, socket) do
    {:noreply,
     socket
     |> assign(:confirm_deactivate_id, nil)
     |> assign(:confirm_deactivate_room, nil)
     |> stream_rooms()}
  end

  # The armed "deactivate room" confirmation timed out; cancel it so an
  # accidental close can't happen after the moderator walked away.
  def handle_info(:reset_room_confirm, socket) do
    {:noreply,
     socket
     |> assign(:confirm_deactivate_id, nil)
     |> assign(:confirm_deactivate_room, nil)
     |> stream_rooms()}
  end

  def handle_event("toggle_room_active", %{"id" => id}, socket) do
    room = Events.get_room!(id)

    # Opening a room is a single click; deactivating arms a confirmation so a
    # moderator can't accidentally hide questions from visitors.
    if room.is_active do
      Process.send_after(self(), :reset_room_confirm, @deactivate_confirm_timeout)

      {:noreply,
       socket
       |> assign(:confirm_deactivate_id, room.id)
       |> assign(:confirm_deactivate_room, room)
       |> stream_rooms()}
    else
      case update_room_status(socket, room, true) do
        {:ok, socket} -> {:noreply, stream_rooms(socket)}
        {:error, socket} -> {:noreply, socket}
      end
    end
  end

  def handle_event("confirm_room_inactive", %{"id" => id}, socket) do
    room = Events.get_room!(id)

    case update_room_status(socket, room, false) do
      {:ok, socket} -> {:noreply, stream_rooms(socket)}
      {:error, socket} -> {:noreply, socket}
    end
  end

  def handle_event("cancel_room_inactive", %{"id" => id}, socket) do
    socket =
      if socket.assigns[:confirm_deactivate_id] == id do
        socket
        |> assign(:confirm_deactivate_id, nil)
        |> assign(:confirm_deactivate_room, nil)
      else
        socket
      end

    {:noreply, stream_rooms(socket)}
  end

  # Closes the centered deactivate-confirmation modal, e.g. from its close
  # button or outside clicks; the panel's own controls use `cancel_room_inactive`.
  def handle_event("close_deactivate_confirm", _, socket) do
    {:noreply,
     socket
     |> assign(:confirm_deactivate_id, nil)
     |> assign(:confirm_deactivate_room, nil)}
  end

  defp update_room_status(socket, room, is_active) do
    case Events.update_room(room, %{"is_active" => is_active}) do
      {:ok, _updated_room} ->
        {:ok,
         socket
         |> assign(:confirm_deactivate_id, nil)
         |> assign(:confirm_deactivate_room, nil)}

      {:error, changeset} ->
        errors = Enum.map_join(changeset.errors, ", ", fn {key, {msg, _}} -> "#{key} #{msg}" end)

        {:error,
         socket
         |> assign(:confirm_deactivate_id, nil)
         |> assign(:confirm_deactivate_room, nil)
         |> put_flash(:error, "Failed to update room status: #{errors}")}
    end
  end

  defp stream_rooms(socket) do
    rooms = rooms_for(socket.assigns.current_user)

    socket
    |> assign(:rooms_count, length(rooms))
    |> stream(:rooms, Enum.with_index(rooms, 1),
      dom_id: fn {room, _index} -> "room-" <> room.id end,
      reset: true
    )
  end

  defp rooms_for(current_user) do
    Events.list_rooms_for_moderator(current_user.id)
  end

  def render(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-5xl mx-auto px-6 pt-12 sm:pt-16 pb-24">
        <header class="border-b border-line pb-8">
          <div class="flex flex-col md:flex-row md:items-end md:justify-between gap-6">
            <div>
              <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 flex items-center gap-2.5">
                <span class="w-2 h-2 bg-accent"></span> Moderator
              </p>
              <h1 class="mt-4 text-3xl sm:text-4xl font-semibold tracking-[-0.03em] leading-[1.05] text-ink">
                Your Event Rooms
              </h1>
            </div>
            <p class="text-sm leading-relaxed text-ink-2 md:max-w-xs md:text-right">
              Select an event room to moderate live questions.
            </p>
          </div>
        </header>

        <div id="moderator-rooms" phx-update="stream">
          <div id="rooms-empty" class="hidden only:block py-16 text-center">
            <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
              No assigned rooms found
            </p>
            <p class="mt-2 text-[13px] leading-relaxed text-ink-3">
              Contact your Administrator to create or assign a room to your account.
            </p>
          </div>

          <div
            :for={{id, {room, index}} <- @streams.rooms}
            id={id}
            class="group grid grid-cols-12 gap-x-4 sm:gap-x-6 items-center py-5 border-b border-line hover:bg-surface transition-colors"
          >
            <div class="col-span-1 hidden sm:block">
              <span class="font-mono text-xs text-ink-3 tabular-nums">{index}</span>
            </div>

            <div class="col-span-11 sm:col-span-5 min-w-0">
              <h3 class="text-[17px] font-semibold tracking-[-0.01em] text-ink truncate">
                {room.title}
              </h3>
              <p class="mt-0.5 font-mono text-xs text-ink-3">/r/{room.slug}</p>
            </div>

            <div class="col-span-4 sm:col-span-2 flex items-center gap-2.5">
              <.status_toggle room={room} />
              <span class={[
                "font-mono text-[11px] uppercase tracking-[0.14em]",
                if(room.is_active, do: "text-ink-2", else: "text-ink-3")
              ]}>
                <%= if room.is_active do %>
                  Active
                <% else %>
                  Inactive
                <% end %>
              </span>
            </div>

            <div class="col-span-8 sm:col-span-3 flex items-center justify-end gap-5">
              <.link
                navigate={~p"/moderator/r/#{room.slug}"}
                class="text-sm font-medium text-ink underline-offset-4 hover:underline transition-colors"
              >
                Open Dashboard →
              </.link>
              <.link
                href={~p"/r/#{room.slug}"}
                target="_blank"
                aria-label="Open audience page in a new tab"
                class="w-9 h-9 rounded border border-line-strong flex items-center justify-center text-ink-2 hover:border-ink hover:text-ink transition-colors"
              >
                <.icon name="hero-arrow-top-right-on-square" class="size-4" />
              </.link>
            </div>
          </div>
        </div>
      </div>

      <!-- Deactivate Room Confirmation Modal -->
      <%= if @confirm_deactivate_room do %>
        <.modal close_event="close_deactivate_confirm">
          <div id="deactivate-confirm-modal">
            <.deactivate_confirm room={@confirm_deactivate_room} variant="modal" />
          </div>
        </.modal>
      <% end %>
    </QaAppWeb.Layouts.app>
    """
  end
end
