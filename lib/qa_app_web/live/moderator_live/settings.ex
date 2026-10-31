defmodule QaAppWeb.ModeratorLive.Settings do
  use QaAppWeb, :live_view

  alias QaApp.Events
  alias QaApp.RoomCapacity
  alias QaAppWeb.ModeratorLive.RoomAuth

  def mount(params, _session, socket) do
    case RoomAuth.authorize(socket, params) do
      {:ok, socket} ->
        {:ok,
         socket
         |> assign(:visitor_count, RoomCapacity.count(socket.assigns.room.id))
         |> assign(:settings_form, settings_form(socket.assigns.room))}

      {:redirect, socket} ->
        {:ok, socket}
    end
  end

  def handle_event("save_settings", %{"room" => room_params}, socket) do
    room = socket.assigns.room
    room_params = normalize_is_active(room_params)

    case Events.update_room(room, room_params) do
      {:ok, updated_room} ->
        {:noreply,
         socket
         |> assign(:room, updated_room)
         |> assign(:settings_form, settings_form(updated_room))
         |> put_flash(:info, "Room settings updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :settings_form, to_form(changeset))}
    end
  end

  # The not-open banner's one-click action: opens an inactive room directly
  # from the settings page.
  def handle_event("toggle_room_active", %{"id" => id}, socket) do
    room = socket.assigns.room

    if room.id == id && !room.is_active do
      case Events.update_room(room, %{"is_active" => true}) do
        {:ok, updated_room} ->
          {:noreply,
           socket
           |> assign(:room, updated_room)
           |> assign(:settings_form, settings_form(updated_room))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to open the room.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:room_settings_updated, room}, socket) do
    {:noreply,
     socket
     |> assign(:room, room)
     |> assign(:settings_form, settings_form(room))}
  end

  # Visitor presence changed (join/leave); refresh the live count.
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :visitor_count, RoomCapacity.count(socket.assigns.room.id))}
  end

  defp settings_form(room), do: Events.change_room(room) |> to_form()

  # The toggle renders a hidden `false` plus a visible checkbox for the same
  # field, so LiveView may deliver `is_active` as a plain string or (when
  # checked) as the list ["false", "true"]. Coerce it to a single value the
  # changeset can cast.
  defp normalize_is_active(params) do
    case Map.get(params, "is_active") do
      nil -> params
      ["false", "true"] -> Map.put(params, "is_active", "true")
      ["true"] -> Map.put(params, "is_active", "true")
      value when value in [true, "true"] -> Map.put(params, "is_active", "true")
      value when value in [false, "false"] -> Map.put(params, "is_active", "false")
      _other -> Map.put(params, "is_active", "false")
    end
  end

  def render(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-6xl mx-auto px-6 pt-12 sm:pt-16 pb-24">
        <%= if !@room.is_active do %>
          <.room_not_open_banner room={@room} />
        <% end %>

        <!-- Masthead -->
        <header class="border-b border-line pb-8">
          <div class="flex flex-col md:flex-row md:items-end md:justify-between gap-6">
            <div>
              <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 flex items-center gap-2.5">
                <span class="w-2 h-2 bg-accent"></span>
                Moderator Dashboard
                <span class="text-ink-3/40 normal-case tracking-normal">/r/{@room.slug}</span>
              </p>
              <h1 class="mt-4 text-3xl sm:text-4xl font-semibold tracking-[-0.03em] leading-[1.05] text-ink">
                {@room.title}
              </h1>
            </div>

            <div class="flex items-center gap-3">
              <span
                id="moderator-visitor-count"
                class="inline-flex items-center gap-1.5 h-10 px-3 rounded border border-line-strong bg-transparent font-mono text-[11px] uppercase tracking-[0.14em] text-ink-2 tabular-nums"
              >
                <span class="w-1.5 h-1.5 rounded-full bg-accent"></span>
                {@visitor_count}
                <%= if @room.is_active do %>
                  live
                <% else %>
                  waiting
                <% end %>
                <%= if @room.max_visitors do %>
                  <span class="text-ink-3">/ {@room.max_visitors}</span>
                <% end %>
              </span>

              <.link
                href={~p"/moderator/r/#{@room.slug}/export.csv"}
                target="_blank"
                class="inline-flex items-center gap-2 h-10 px-4 rounded border border-line-strong bg-transparent text-ink text-sm font-medium hover:border-ink transition-colors duration-150"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Export
              </.link>
            </div>
          </div>
        </header>

        <Layouts.room_tabs room={@room} active={:settings} />

        <!-- Room Expiry (read-only, locked at creation) -->
        <section class="max-w-2xl mt-10">
          <div class="rounded border border-line-strong p-4">
            <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
              Room Expires
            </p>
            <p id="room-expiry" class="mt-1 text-sm text-ink tabular-nums">
              <.local_datetime id="room-expiry-local" datetime={@room.expires_at} />
            </p>
            <p class="mt-1 text-xs text-ink-3">
              Rooms are automatically cleaned up after their expiry. The expiry
              is fixed when the room is created and cannot be changed.
            </p>
          </div>
        </section>

        <!-- Event Settings Form -->
        <section class="max-w-2xl mt-10">
          <h3 class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
            Event Settings
          </h3>

          <.form
            for={@settings_form}
            id="settings-form"
            phx-submit="save_settings"
            class="mt-6 space-y-5"
          >
            <div>
              <.input field={@settings_form[:title]} type="text" label="Event Title" />
            </div>

            <div>
              <.input field={@settings_form[:intro_text]} type="textarea" label="Intro" />
            </div>

            <div>
              <.input
                field={@settings_form[:char_limit]}
                type="number"
                label="Max Character Limit per Question"
              />
            </div>

            <div>
              <.input
                field={@settings_form[:max_visitors]}
                type="number"
                min="1"
                placeholder="Leave empty for unlimited"
                label="Max Concurrent Visitors"
              />
              <p class="mt-1 text-xs leading-relaxed text-ink-3">
                The room stops admitting new visitors
                once this many people are connected.
              </p>
            </div>

            <div>
              <.toggle
                field={@settings_form[:is_active]}
                label="Room is open"
                hint="Visitors can join and submit questions while the room is active. Turning the room off keeps current visitors connected, showing them a waiting page until it is ready again."
              />
            </div>

            <button
              type="submit"
              class="w-full inline-flex items-center justify-center h-10 px-4 rounded bg-ink text-paper text-sm font-medium hover:bg-accent transition-colors duration-150"
            >
              Save Settings
            </button>
          </.form>
        </section>
      </div>
    </QaAppWeb.Layouts.app>
    """
  end
end
