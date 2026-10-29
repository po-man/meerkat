defmodule QaAppWeb.AdminLive.Index do
  use QaAppWeb, :live_view

  alias QaApp.Events
  alias QaApp.Events.Room
  alias QaApp.Accounts
  alias QaApp.RoomCapacity

  def mount(_params, _session, socket) do
    users = Accounts.list_users()
    moderators = Accounts.list_moderators()

    if connected?(socket) do
      Events.subscribe_rooms()
    end

    room_form = to_form(Events.change_room(%Room{}))

    {:ok,
     socket
     |> stream_rooms()
     |> assign(:users, users)
     |> assign(:moderators, moderators)
     |> assign(:room_form, room_form)
     |> assign(:editing_room, nil)
     |> assign(:edit_room_form, nil)
     |> assign(:show_create_room_modal?, false)
     |> assign(:show_create_moderator_modal?, false)
     |> assign(:show_configure_room_modal?, false)
     |> assign(:moderator_form, to_form(%{"username" => "", "password" => ""}, as: :moderator))}
  end

  def handle_info({:room_expired, _room_id}, socket) do
    {:noreply, stream_rooms(socket)}
  end

  # A visitor joined or left a room; refresh the live visitor counts.
  #
  # The counts are rendered inside streamed table rows, and LiveView only
  # morphs streamed children when the collection itself is re-streamed — an
  # outer assign change alone does not update the rows in the browser. So we
  # recompute the counts and re-stream the rooms together.
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", topic: "room:" <> _room_id},
        socket
      ) do
    {:noreply, stream_rooms(socket)}
  end

  # The admin is subscribed to the room topics for presence diffs, so it also
  # sees the app's plain broadcasts; these are already reflected via the rooms
  # list and are otherwise irrelevant here.
  def handle_info({:room_settings_updated, _room}, socket), do: {:noreply, socket}
  def handle_info({:room_visitors_expelled, _session_ids}, socket), do: {:noreply, socket}

  # A room's settings changed from another view (moderator dashboard, settings
  # tab, or a status toggle). Refresh the streamed rows so the status toggle
  # and labels stay live.
  def handle_info({:rooms_settings_updated, _room}, socket) do
    {:noreply, stream_rooms(socket)}
  end

  def handle_event("open_create_room", _, socket) do
    {:noreply, assign(socket, :show_create_room_modal?, true)}
  end

  def handle_event("close_create_room", _, socket) do
    {:noreply, assign(socket, :show_create_room_modal?, false)}
  end

  def handle_event("open_configure_room", %{"id" => id}, socket) do
    room = Events.get_room!(id)
    edit_form = to_form(Events.change_room(room))

    {:noreply,
     socket
     |> assign(:editing_room, room)
     |> assign(:edit_room_form, edit_form)
     |> assign(:show_configure_room_modal?, true)}
  end

  def handle_event("close_configure_room", _, socket) do
    {:noreply,
     socket
     |> assign(:show_configure_room_modal?, false)
     |> assign(:editing_room, nil)
     |> assign(:edit_room_form, nil)}
  end

  def handle_event("open_create_moderator", _, socket) do
    {:noreply, assign(socket, :show_create_moderator_modal?, true)}
  end

  def handle_event("close_create_moderator", _, socket) do
    {:noreply, assign(socket, :show_create_moderator_modal?, false)}
  end

  def handle_event("create_room", %{"room" => room_params}, socket) do
    room_params =
      room_params
      |> normalize_is_active()
      |> then(fn params ->
        if params["moderator_id"] == "",
          do: Map.delete(params, "moderator_id"),
          else: params
      end)

    case Events.create_room(room_params) do
      {:ok, _room} ->
        {:noreply,
         socket
         |> stream_rooms()
         |> assign(:show_create_room_modal?, false)
         |> assign(:room_form, to_form(Events.change_room(%Room{})))
         |> put_flash(:info, "Room created successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :room_form, to_form(changeset))}
    end
  end

  def handle_event("update_room", %{"room" => room_params}, socket) do
    room = socket.assigns.editing_room

    room_params =
      room_params
      |> normalize_is_active()
      |> then(fn params ->
        if params["moderator_id"] == "",
          do: Map.put(params, "moderator_id", nil),
          else: params
      end)

    case Events.update_room(room, room_params) do
      {:ok, _updated_room} ->
        {:noreply,
         socket
         |> stream_rooms()
         |> assign(:show_configure_room_modal?, false)
         |> assign(:editing_room, nil)
         |> assign(:edit_room_form, nil)
         |> put_flash(:info, "Room configured successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_room_form, to_form(changeset))}
    end
  end

  def handle_event(
        "create_moderator",
        %{"moderator" => %{"username" => username, "password" => password}},
        socket
      ) do
    case Accounts.create_moderator(%{"username" => username, "password" => password}) do
      {:ok, _moderator} ->
        users = Accounts.list_users()
        moderators = Accounts.list_moderators()

        {:noreply,
         socket
         |> assign(:users, users)
         |> assign(:moderators, moderators)
         |> assign(:show_create_moderator_modal?, false)
         |> put_flash(:info, "Moderator account created successfully.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create Moderator account.")}
    end
  end

  def handle_event("delete_room", %{"id" => id}, socket) do
    room = Events.get_room!(id)
    {:ok, _} = Events.delete_room(room)
    {:noreply, stream_rooms(socket)}
  end

  def handle_event("toggle_room_active", %{"id" => id}, socket) do
    room = Events.get_room!(id)

    case Events.update_room(room, %{"is_active" => !room.is_active}) do
      {:ok, _updated_room} ->
        {:noreply, stream_rooms(socket)}

      {:error, changeset} ->
        errors = Enum.map_join(changeset.errors, ", ", fn {key, {msg, _}} -> "#{key} #{msg}" end)
        {:noreply, put_flash(socket, :error, "Failed to update room status: #{errors}")}
    end
  end

  def render(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-6xl mx-auto px-6 pt-12 sm:pt-16 pb-24">
        <header class="border-b border-line pb-8">
          <div class="flex flex-col lg:flex-row lg:items-end lg:justify-between gap-6">
            <div>
              <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 flex items-center gap-2.5">
                <span class="w-2 h-2 bg-accent"></span> System
              </p>
              <h1 class="mt-4 text-3xl sm:text-4xl font-semibold tracking-[-0.03em] leading-[1.05] text-ink">
                Admin Control Center
              </h1>
              <p class="mt-2 text-sm text-ink-2">
                Manage system rooms, moderators, and event routing.
              </p>
            </div>

            <div class="flex items-center gap-3">
              <span
                id="total-live-visitors"
                class="hidden sm:inline-flex items-center gap-2 h-10 px-3 rounded border border-line-strong bg-transparent font-mono text-[11px] uppercase tracking-[0.14em] text-ink-2 tabular-nums"
              >
                <span class="w-1.5 h-1.5 rounded-full bg-accent motion-safe:animate-pulse"></span>
                {@total_visitors} live
              </span>

              <button
                phx-click="open_create_moderator"
                class="inline-flex items-center gap-2 h-10 px-4 rounded border border-line-strong bg-transparent text-ink text-sm font-medium hover:border-ink transition-colors duration-150"
              >
                <.icon name="hero-user-plus" class="size-4" /> Add Moderator
              </button>

              <button
                phx-click="open_create_room"
                class="inline-flex items-center gap-2 h-10 px-4 rounded bg-ink text-paper text-sm font-medium hover:bg-accent transition-colors duration-150"
              >
                <.icon name="hero-plus" class="size-4" /> Create Room
              </button>
            </div>
          </div>
        </header>

        <!-- Rooms List -->
        <section class="mt-10">
          <div class="flex items-baseline justify-between gap-4 pb-3 border-b border-line">
            <h3 class="text-lg font-semibold tracking-[-0.01em] text-ink">Event Rooms</h3>
            <span class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 tabular-nums">
              {@rooms_count} total
            </span>
          </div>

          <div class="overflow-x-auto">
            <table class="w-full text-left text-sm min-w-[640px]">
              <thead>
                <tr>
                  <th class="py-3 pr-4 font-mono text-[11px] font-normal uppercase tracking-[0.14em] text-ink-3 border-b border-line-strong whitespace-nowrap">
                    Title / Slug
                  </th>
                  <th class="py-3 pr-4 font-mono text-[11px] font-normal uppercase tracking-[0.14em] text-ink-3 border-b border-line-strong whitespace-nowrap">
                    Assigned Moderator
                  </th>
                  <th class="py-3 pr-4 font-mono text-[11px] font-normal uppercase tracking-[0.14em] text-ink-3 border-b border-line-strong whitespace-nowrap">
                    Character Limit
                  </th>
                  <th class="py-3 pr-4 font-mono text-[11px] font-normal uppercase tracking-[0.14em] text-ink-3 border-b border-line-strong whitespace-nowrap">
                    Live Visitors
                  </th>
                  <th class="py-3 pr-4 font-mono text-[11px] font-normal uppercase tracking-[0.14em] text-ink-3 border-b border-line-strong whitespace-nowrap">
                    Status
                  </th>
                  <th class="py-3 pr-4 font-mono text-[11px] font-normal uppercase tracking-[0.14em] text-ink-3 border-b border-line-strong whitespace-nowrap">
                    Expires
                  </th>
                  <th class="py-3 border-b border-line-strong text-right">
                    <span class="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody id="rooms-rows" phx-update="stream">
                <tr
                  :for={{id, room} <- @streams.rooms}
                  id={id}
                  class="border-b border-line hover:bg-surface transition-colors"
                >
                  <td class="py-4 pr-4 align-top">
                    <div class="font-semibold text-ink">{room.title}</div>
                    <div class="mt-0.5 font-mono text-xs text-ink-3">/r/{room.slug}</div>
                  </td>
                  <td class="py-4 pr-4 align-top">
                    <%= if room.moderator do %>
                      <span class="font-mono text-xs text-ink-2">{room.moderator.username}</span>
                    <% else %>
                      <span class="font-mono text-xs text-ink-3">Unassigned</span>
                    <% end %>
                  </td>
                  <td class="py-4 pr-4 align-top font-mono text-xs tabular-nums text-ink-2">
                    {room.char_limit} characters
                  </td>
                  <td class="py-4 pr-4 align-top">
                    <span
                      id={"room-live-#{room.id}"}
                      class="inline-flex items-center gap-1.5 font-mono text-xs tabular-nums text-ink-2"
                    >
                      <span class="w-1.5 h-1.5 rounded-full bg-accent"></span>
                      {Map.get(@visitor_counts, room.id, 0)}
                      <%= if room.max_visitors do %>
                        <span class="text-ink-3">/ {room.max_visitors}</span>
                      <% end %>
                    </span>
                  </td>
                  <td class="py-4 pr-4 align-top">
                    <div class="flex items-center gap-3">
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
                  </td>
                  <td class="py-4 pr-4 align-top font-mono text-xs tabular-nums text-ink-2">
                    <.local_datetime id={"room-expiry-#{room.id}"} datetime={room.expires_at} />
                  </td>
                  <td class="py-4 align-top text-right whitespace-nowrap">
                    <div class="inline-flex items-center gap-4">
                      <button
                        phx-click="open_configure_room"
                        phx-value-id={room.id}
                        class="text-[13px] font-medium text-ink-2 hover:text-ink transition-colors underline-offset-4 hover:underline"
                      >
                        Configure
                      </button>
                      <.link
                        navigate={~p"/moderator/r/#{room.slug}"}
                        class="text-[13px] font-medium text-ink-2 hover:text-ink transition-colors underline-offset-4 hover:underline"
                      >
                        Moderate
                      </.link>
                      <button
                        phx-click="delete_room"
                        phx-value-id={room.id}
                        data-confirm="Are you sure you want to delete this room?"
                        class="text-[13px] font-medium text-danger hover:underline underline-offset-4 transition-colors"
                      >
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <!-- Configure Room Modal -->
        <%= if @show_configure_room_modal? do %>
          <.modal close_event="close_configure_room">
            <div>
              <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                Configure Room
              </p>
              <h3 class="mt-2 text-xl font-semibold tracking-[-0.02em] text-ink">
                Room Settings
              </h3>
            </div>

            <.form
              for={@edit_room_form}
              id="configure-room-form"
              phx-submit="update_room"
              class="space-y-4"
            >
              <.input field={@edit_room_form[:title]} type="text" required label="Room Title" />

              <.input
                field={@edit_room_form[:slug]}
                type="text"
                required
                label="Room Slug (URL identifier)"
              />

              <div>
                <label
                  for="configure-room-moderator"
                  class="block font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 mb-2"
                >
                  Assigned Moderator
                </label>
                <select
                  id="configure-room-moderator"
                  name="room[moderator_id]"
                  class="w-full h-10 px-3 rounded bg-transparent border border-line-strong text-sm text-ink focus:outline-none focus:border-ink transition-colors"
                >
                  <option value="">Select Moderator (Unassigned)...</option>
                  <%= for moderator <- @moderators do %>
                    <option
                      value={moderator.id}
                      selected={@edit_room_form[:moderator_id].value == moderator.id}
                    >
                      {moderator.username}
                    </option>
                  <% end %>
                </select>
              </div>

              <.input
                field={@edit_room_form[:char_limit]}
                type="number"
                required
                label="Max Character Limit"
              />

              <.input
                field={@edit_room_form[:max_visitors]}
                type="number"
                min="1"
                label="Max Concurrent Visitors"
              />
              <p class="mt-1 text-xs leading-relaxed text-ink-3">
                Leave empty for unlimited. Existing visitors are removed
                (newest first) if you lower this below the current count.
              </p>

              <.toggle
                field={@edit_room_form[:is_active]}
                label="Room is open"
                hint="Visitors can join and submit questions while the room is active."
              />

              <.input
                field={@edit_room_form[:intro_text]}
                type="textarea"
                label="Intro / Description Text"
              />

              <div class="flex items-center justify-end gap-3 pt-2">
                <button
                  type="button"
                  phx-click="close_configure_room"
                  class="inline-flex items-center justify-center h-10 px-4 rounded border border-line-strong bg-transparent text-ink text-sm font-medium hover:border-ink transition-colors duration-150"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="inline-flex items-center justify-center h-10 px-4 rounded bg-ink text-paper text-sm font-medium hover:bg-accent transition-colors duration-150"
                >
                  Save Changes
                </button>
              </div>
            </.form>
          </.modal>
        <% end %>

        <!-- Create Room Modal -->
        <%= if @show_create_room_modal? do %>
          <.modal close_event="close_create_room">
            <div>
              <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                Create Room
              </p>
              <h3 class="mt-2 text-xl font-semibold tracking-[-0.02em] text-ink">
                New Event Room
              </h3>
            </div>

            <.form for={@room_form} id="create-room-form" phx-submit="create_room" class="space-y-4">
              <.input
                field={@room_form[:slug]}
                type="text"
                placeholder="q4-townhall"
                required
                label="Room Slug (URL identifier)"
              />

              <.input
                field={@room_form[:title]}
                type="text"
                placeholder="All-Hands Q&A"
                required
                label="Event Title"
              />

              <div>
                <label
                  for="create-room-moderator"
                  class="block font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 mb-2"
                >
                  Assign Moderator
                </label>
                <select
                  id="create-room-moderator"
                  name="room[moderator_id]"
                  class="w-full h-10 px-3 rounded bg-transparent border border-line-strong text-sm text-ink focus:outline-none focus:border-ink transition-colors"
                >
                  <option value="">Select Moderator...</option>
                  <%= for moderator <- @moderators do %>
                    <option value={moderator.id}>{moderator.username}</option>
                  <% end %>
                </select>
              </div>

              <.input
                field={@room_form[:char_limit]}
                type="number"
                value="320"
                label="Max Character Limit"
              />

              <.input
                field={@room_form[:max_visitors]}
                type="number"
                min="1"
                placeholder="250"
                label="Max Concurrent Visitors"
              />

              <.input
                field={@room_form[:expires_in]}
                type="select"
                value="7 days"
                options={Room.expiry_options()}
                label="Room Expiry (auto-cleanup)"
              />

              <.toggle
                field={@room_form[:is_active]}
                label="Room is open"
                hint="Visitors can join and submit questions while the room is active."
              />

              <div class="flex items-center justify-end gap-3 pt-2">
                <button
                  type="button"
                  phx-click="close_create_room"
                  class="inline-flex items-center justify-center h-10 px-4 rounded border border-line-strong bg-transparent text-ink text-sm font-medium hover:border-ink transition-colors duration-150"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="inline-flex items-center justify-center h-10 px-4 rounded bg-ink text-paper text-sm font-medium hover:bg-accent transition-colors duration-150"
                >
                  Create Room
                </button>
              </div>
            </.form>
          </.modal>
        <% end %>

        <!-- Create Moderator Modal -->
        <%= if @show_create_moderator_modal? do %>
          <.modal close_event="close_create_moderator">
            <div>
              <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                Add Moderator
              </p>
              <h3 class="mt-2 text-xl font-semibold tracking-[-0.02em] text-ink">
                Moderator Account
              </h3>
            </div>

            <.form
              for={@moderator_form}
              id="create-moderator-form"
              phx-submit="create_moderator"
              class="space-y-4"
            >
              <.input
                field={@moderator_form[:username]}
                type="text"
                required
                label="Username"
              />

              <.input
                field={@moderator_form[:password]}
                type="password"
                required
                label="Initial Password"
              />

              <div class="flex items-center justify-end gap-3 pt-2">
                <button
                  type="button"
                  phx-click="close_create_moderator"
                  class="inline-flex items-center justify-center h-10 px-4 rounded border border-line-strong bg-transparent text-ink text-sm font-medium hover:border-ink transition-colors duration-150"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="inline-flex items-center justify-center h-10 px-4 rounded bg-ink text-paper text-sm font-medium hover:bg-accent transition-colors duration-150"
                >
                  Create Account
                </button>
              </div>
            </.form>
          </.modal>
        <% end %>
      </div>
    </QaAppWeb.Layouts.app>
    """
  end

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

  defp stream_rooms(socket) do
    rooms = Events.list_rooms()
    socket = sync_presence_subscriptions(socket, rooms)
    visitor_counts = Map.new(rooms, &{&1.id, RoomCapacity.count(&1.id)})

    socket
    |> assign(:rooms_count, length(rooms))
    |> assign(:visitor_counts, visitor_counts)
    |> assign(:total_visitors, Enum.sum(Map.values(visitor_counts)))
    |> stream(:rooms, rooms, dom_id: &("room-" <> &1.id), reset: true)
  end

  # Keeps the admin LiveView subscribed to each room's presence topic so live
  # visitor counts stay in sync, subscribing to new rooms and unsubscribing
  # from removed/deleted ones.
  defp sync_presence_subscriptions(socket, rooms) do
    new_topics = MapSet.new(rooms, fn room -> "room:#{room.id}" end)
    old_topics = Map.get(socket.assigns, :presence_topics, MapSet.new())

    new_topics
    |> MapSet.difference(old_topics)
    |> Enum.each(fn topic -> Phoenix.PubSub.subscribe(QaApp.PubSub, topic) end)

    old_topics
    |> MapSet.difference(new_topics)
    |> Enum.each(fn topic -> Phoenix.PubSub.unsubscribe(QaApp.PubSub, topic) end)

    assign(socket, :presence_topics, new_topics)
  end
end
