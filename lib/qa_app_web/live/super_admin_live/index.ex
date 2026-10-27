defmodule QaAppWeb.SuperAdminLive.Index do
  use QaAppWeb, :live_view

  alias QaApp.Events
  alias QaApp.Events.Room
  alias QaApp.Accounts

  def mount(_params, _session, socket) do
    rooms = Events.list_rooms()
    users = Accounts.list_users()
    room_admins = Enum.filter(users, fn u -> u.role == :room_admin end)

    if connected?(socket) do
      Events.subscribe_rooms()
    end

    room_form = to_form(Events.change_room(%Room{}))

    {:ok,
     socket
     |> assign(:rooms, rooms)
     |> assign(:users, users)
     |> assign(:room_admins, room_admins)
     |> assign(:room_form, room_form)
     |> assign(:editing_room, nil)
     |> assign(:edit_room_form, nil)
     |> assign(:show_create_room_modal?, false)
     |> assign(:show_create_admin_modal?, false)
     |> assign(:show_configure_room_modal?, false)
     |> assign(:admin_username, "")
     |> assign(:admin_password, "")}
  end

  def handle_info({:room_expired, _room_id}, socket) do
    {:noreply, assign(socket, :rooms, Events.list_rooms())}
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

  def handle_event("open_create_admin", _, socket) do
    {:noreply, assign(socket, :show_create_admin_modal?, true)}
  end

  def handle_event("close_create_admin", _, socket) do
    {:noreply, assign(socket, :show_create_admin_modal?, false)}
  end

  def handle_event("create_room", %{"room" => room_params}, socket) do
    room_params =
      if room_params["admin_id"] == "", do: Map.delete(room_params, "admin_id"), else: room_params

    case Events.create_room(room_params) do
      {:ok, _room} ->
        rooms = Events.list_rooms()

        {:noreply,
         socket
         |> assign(:rooms, rooms)
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
      if room_params["admin_id"] == "",
        do: Map.put(room_params, "admin_id", nil),
        else: room_params

    case Events.update_room(room, room_params) do
      {:ok, _updated_room} ->
        rooms = Events.list_rooms()

        {:noreply,
         socket
         |> assign(:rooms, rooms)
         |> assign(:show_configure_room_modal?, false)
         |> assign(:editing_room, nil)
         |> assign(:edit_room_form, nil)
         |> put_flash(:info, "Room configured successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_room_form, to_form(changeset))}
    end
  end

  def handle_event(
        "create_room_admin",
        %{"admin" => %{"username" => username, "password" => password}},
        socket
      ) do
    case Accounts.create_room_admin(%{"username" => username, "password" => password}) do
      {:ok, _admin} ->
        users = Accounts.list_users()
        room_admins = Enum.filter(users, fn u -> u.role == :room_admin end)

        {:noreply,
         socket
         |> assign(:users, users)
         |> assign(:room_admins, room_admins)
         |> assign(:show_create_admin_modal?, false)
         |> put_flash(:info, "Room Admin account created successfully.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create Room Admin account.")}
    end
  end

  def handle_event("delete_room", %{"id" => id}, socket) do
    room = Events.get_room!(id)
    {:ok, _} = Events.delete_room(room)
    rooms = Events.list_rooms()
    {:noreply, assign(socket, :rooms, rooms)}
  end

  defp format_expiry(%DateTime{} = expires_at) do
    Calendar.strftime(expires_at, "%b %d, %Y %I:%M %p") <> " UTC"
  end

  defp format_expiry(_), do: "—"

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
                Super Admin Control Center
              </h1>
              <p class="mt-2 text-sm text-ink-2">
                Manage system rooms, administrators, and event routing.
              </p>
            </div>

            <div class="flex items-center gap-3">
              <button
                phx-click="open_create_admin"
                class="inline-flex items-center gap-2 h-10 px-4 rounded border border-line-strong bg-transparent text-ink text-sm font-medium hover:border-ink transition-colors duration-150"
              >
                <.icon name="hero-user-plus" class="size-4" /> Add Room Admin
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
              {length(@rooms)} total
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
                    Assigned Admin
                  </th>
                  <th class="py-3 pr-4 font-mono text-[11px] font-normal uppercase tracking-[0.14em] text-ink-3 border-b border-line-strong whitespace-nowrap">
                    Word Limit
                  </th>
                  <th class="py-3 pr-4 font-mono text-[11px] font-normal uppercase tracking-[0.14em] text-ink-3 border-b border-line-strong whitespace-nowrap">
                    Expires
                  </th>
                  <th class="py-3 border-b border-line-strong text-right">
                    <span class="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                <%= for room <- @rooms do %>
                  <tr class="border-b border-line hover:bg-surface transition-colors">
                    <td class="py-4 pr-4 align-top">
                      <div class="font-semibold text-ink">{room.title}</div>
                      <div class="mt-0.5 font-mono text-xs text-ink-3">/r/{room.slug}</div>
                    </td>
                    <td class="py-4 pr-4 align-top">
                      <%= if room.admin do %>
                        <span class="font-mono text-xs text-ink-2">{room.admin.username}</span>
                      <% else %>
                        <span class="font-mono text-xs text-ink-3">Unassigned</span>
                      <% end %>
                    </td>
                    <td class="py-4 pr-4 align-top font-mono text-xs tabular-nums text-ink-2">
                      {room.word_limit} words
                    </td>
                    <td class="py-4 pr-4 align-top font-mono text-xs tabular-nums text-ink-2">
                      {format_expiry(room.expires_at)}
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
                          navigate={~p"/admin/r/#{room.slug}"}
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
                <% end %>
              </tbody>
            </table>
          </div>
        </section>

        <!-- Configure Room Modal -->
        <%= if @show_configure_room_modal? do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40">
            <div class="bg-paper border border-line-strong rounded-lg p-6 sm:p-8 max-w-md w-full space-y-5 relative">
              <button
                phx-click="close_configure_room"
                aria-label="Close"
                class="absolute top-3 right-3 w-9 h-9 rounded border border-transparent hover:border-line-strong flex items-center justify-center text-ink-3 hover:text-ink transition-colors"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>

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
                    for="configure-room-admin"
                    class="block font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 mb-2"
                  >
                    Assigned Room Admin
                  </label>
                  <select
                    id="configure-room-admin"
                    name="room[admin_id]"
                    class="w-full h-10 px-3 rounded bg-transparent border border-line-strong text-sm text-ink focus:outline-none focus:border-ink transition-colors"
                  >
                    <option value="">Select Room Admin (Unassigned)...</option>
                    <%= for admin <- @room_admins do %>
                      <option value={admin.id} selected={@edit_room_form[:admin_id].value == admin.id}>
                        {admin.username}
                      </option>
                    <% end %>
                  </select>
                </div>

                <.input
                  field={@edit_room_form[:word_limit]}
                  type="number"
                  required
                  label="Max Word Limit"
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
            </div>
          </div>
        <% end %>

        <!-- Create Room Modal -->
        <%= if @show_create_room_modal? do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40">
            <div class="bg-paper border border-line-strong rounded-lg p-6 sm:p-8 max-w-md w-full space-y-5 relative">
              <button
                phx-click="close_create_room"
                aria-label="Close"
                class="absolute top-3 right-3 w-9 h-9 rounded border border-transparent hover:border-line-strong flex items-center justify-center text-ink-3 hover:text-ink transition-colors"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>

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
                    for="create-room-admin"
                    class="block font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 mb-2"
                  >
                    Assign Room Admin
                  </label>
                  <select
                    id="create-room-admin"
                    name="room[admin_id]"
                    class="w-full h-10 px-3 rounded bg-transparent border border-line-strong text-sm text-ink focus:outline-none focus:border-ink transition-colors"
                  >
                    <option value="">Select Room Admin...</option>
                    <%= for admin <- @room_admins do %>
                      <option value={admin.id}>{admin.username}</option>
                    <% end %>
                  </select>
                </div>

                <.input
                  field={@room_form[:word_limit]}
                  type="number"
                  value="50"
                  label="Max Word Limit"
                />

                <.input
                  field={@room_form[:expires_in]}
                  type="select"
                  value="7 days"
                  options={Room.expiry_options()}
                  label="Room Expiry (auto-cleanup)"
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
            </div>
          </div>
        <% end %>

        <!-- Create Admin Modal -->
        <%= if @show_create_admin_modal? do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40">
            <div class="bg-paper border border-line-strong rounded-lg p-6 sm:p-8 max-w-md w-full space-y-5 relative">
              <button
                phx-click="close_create_admin"
                aria-label="Close"
                class="absolute top-3 right-3 w-9 h-9 rounded border border-transparent hover:border-line-strong flex items-center justify-center text-ink-3 hover:text-ink transition-colors"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>

              <div>
                <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                  Add Administrator
                </p>
                <h3 class="mt-2 text-xl font-semibold tracking-[-0.02em] text-ink">
                  Room Admin Account
                </h3>
              </div>

              <.form :let={f} for={%{}} action="#" phx-submit="create_room_admin" class="space-y-4">
                <.input
                  field={f[:username]}
                  name="admin[username]"
                  type="text"
                  required
                  label="Username"
                />

                <.input
                  field={f[:password]}
                  name="admin[password]"
                  type="password"
                  required
                  label="Initial Password"
                />

                <div class="flex items-center justify-end gap-3 pt-2">
                  <button
                    type="button"
                    phx-click="close_create_admin"
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
            </div>
          </div>
        <% end %>
      </div>
    </QaAppWeb.Layouts.app>
    """
  end
end
