defmodule QaAppWeb.SuperAdminLive.Index do
  use QaAppWeb, :live_view

  alias QaApp.Events
  alias QaApp.Accounts

  def mount(_params, _session, socket) do
    rooms = Events.list_rooms()
    users = Accounts.list_users()
    room_admins = Enum.filter(users, fn u -> u.role == :room_admin end)

    room_form = to_form(Events.change_room(%QaApp.Events.Room{}))

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
         |> assign(:room_form, to_form(Events.change_room(%QaApp.Events.Room{})))
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

  def render(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto px-4 py-8 space-y-8">
        <div class="flex items-center justify-between border-b border-slate-700/60 pb-6">
          <div>
            <h1 class="text-3xl font-extrabold text-white flex items-center gap-3">
              <.icon name="hero-shield-check" class="w-8 h-8 text-amber-400" />
              Super Admin Control Center
            </h1>
            <p class="text-sm text-slate-400 mt-1">
              Manage system rooms, administrators, and event routing.
            </p>
          </div>

          <div class="flex items-center gap-3">
            <button
              phx-click="open_create_admin"
              class="px-4 py-2.5 rounded-xl text-sm font-semibold bg-slate-700 hover:bg-slate-600 text-white transition-all border border-slate-600 flex items-center gap-2"
            >
              <.icon name="hero-user-plus" class="w-4 h-4" /> Add Room Admin
            </button>

            <button
              phx-click="open_create_room"
              class="px-4 py-2.5 rounded-xl text-sm font-semibold bg-gradient-to-r from-amber-500 to-orange-600 hover:from-amber-600 hover:to-orange-700 text-white transition-all shadow-lg shadow-amber-500/20 flex items-center gap-2"
            >
              <.icon name="hero-plus" class="w-4 h-4" /> Create Room
            </button>
          </div>
        </div>

        <!-- Rooms List Table -->
        <div class="bg-slate-800/80 backdrop-blur-md rounded-2xl border border-slate-700/60 shadow-xl overflow-hidden">
          <div class="p-6 border-b border-slate-700/60 flex items-center justify-between">
            <h3 class="text-lg font-bold text-white">Event Rooms ({length(@rooms)})</h3>
          </div>

          <div class="overflow-x-auto">
            <table class="w-full text-left text-sm text-slate-300">
              <thead class="bg-slate-900/60 text-xs uppercase text-slate-400 border-b border-slate-700/60">
                <tr>
                  <th class="px-6 py-4">Title / Slug</th>
                  <th class="px-6 py-4">Assigned Admin</th>
                  <th class="px-6 py-4">Word Limit</th>
                  <th class="px-6 py-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-700/40">
                <%= for room <- @rooms do %>
                  <tr class="hover:bg-slate-700/30 transition-all">
                    <td class="px-6 py-4">
                      <div class="font-bold text-white">{room.title}</div>
                      <div class="text-xs text-indigo-400 font-mono">/r/{room.slug}</div>
                    </td>
                    <td class="px-6 py-4">
                      <%= if room.admin do %>
                        <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-semibold bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                          {room.admin.username}
                        </span>
                      <% else %>
                        <span class="text-xs text-slate-500 italic">Unassigned</span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 font-semibold text-slate-300">{room.word_limit} words</td>
                    <td class="px-6 py-4 text-right space-x-2">
                      <button
                        phx-click="open_configure_room"
                        phx-value-id={room.id}
                        class="px-3 py-1.5 rounded-lg text-xs font-semibold bg-amber-600/30 text-amber-300 hover:bg-amber-600/40 border border-amber-500/30"
                      >
                        Configure
                      </button>
                      <.link
                        navigate={~p"/admin/r/#{room.slug}"}
                        class="px-3 py-1.5 rounded-lg text-xs font-semibold bg-indigo-600/30 text-indigo-300 hover:bg-indigo-600/40 border border-indigo-500/30"
                      >
                        Moderate
                      </.link>
                      <button
                        phx-click="delete_room"
                        phx-value-id={room.id}
                        data-confirm="Are you sure you want to delete this room?"
                        class="px-3 py-1.5 rounded-lg text-xs font-semibold bg-rose-600/20 text-rose-300 hover:bg-rose-600/30 border border-rose-500/30"
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Configure Room Modal -->
        <%= if @show_configure_room_modal? do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm">
            <div class="bg-slate-800 border border-slate-700 rounded-3xl p-6 max-w-md w-full space-y-4 shadow-2xl relative">
              <button
                phx-click="close_configure_room"
                class="absolute top-4 right-4 text-slate-400 hover:text-white"
              >
                <.icon name="hero-x-mark" class="w-6 h-6" />
              </button>

              <h3 class="text-xl font-bold text-white">Configure Room Settings</h3>

              <.form
                for={@edit_room_form}
                id="configure-room-form"
                phx-submit="update_room"
                class="space-y-4"
              >
                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Room Title</label>
                  <.input
                    field={@edit_room_form[:title]}
                    type="text"
                    required
                    class="w-full bg-slate-900 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm"
                  />
                </div>

                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Room Slug (URL identifier)</label>
                  <.input
                    field={@edit_room_form[:slug]}
                    type="text"
                    required
                    class="w-full bg-slate-900 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm"
                  />
                </div>

                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Assigned Room Admin</label>
                  <select
                    name="room[admin_id]"
                    class="w-full bg-slate-900 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm"
                  >
                    <option value="">Select Room Admin (Unassigned)...</option>
                    <%= for admin <- @room_admins do %>
                      <option value={admin.id} selected={@edit_room_form[:admin_id].value == admin.id}>
                        {admin.username}
                      </option>
                    <% end %>
                  </select>
                </div>

                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Max Word Limit</label>
                  <.input
                    field={@edit_room_form[:word_limit]}
                    type="number"
                    required
                    class="w-full bg-slate-900 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm"
                  />
                </div>

                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Intro / Description Text</label>
                  <.input
                    field={@edit_room_form[:intro_text]}
                    type="textarea"
                    class="w-full bg-slate-900 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm resize-none h-20"
                  />
                </div>

                <div class="flex items-center justify-end gap-3 pt-2">
                  <button
                    type="button"
                    phx-click="close_configure_room"
                    class="px-4 py-2 rounded-xl text-sm font-semibold bg-slate-700 text-slate-300 hover:bg-slate-600"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="px-4 py-2 rounded-xl text-sm font-semibold bg-amber-500 hover:bg-amber-600 text-white"
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
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm">
            <div class="bg-slate-800 border border-slate-700 rounded-3xl p-6 max-w-md w-full space-y-4 shadow-2xl relative">
              <button
                phx-click="close_create_room"
                class="absolute top-4 right-4 text-slate-400 hover:text-white"
              >
                <.icon name="hero-x-mark" class="w-6 h-6" />
              </button>

              <h3 class="text-xl font-bold text-white">Create New Event Room</h3>

              <.form for={@room_form} id="create-room-form" phx-submit="create_room" class="space-y-4">
                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Room Slug (URL identifier)</label>
                  <.input
                    field={@room_form[:slug]}
                    type="text"
                    placeholder="q4-townhall"
                    required
                    class="w-full bg-slate-900 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm"
                  />
                </div>

                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Event Title</label>
                  <.input
                    field={@room_form[:title]}
                    type="text"
                    placeholder="All-Hands Q&A"
                    required
                    class="w-full bg-slate-900 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm"
                  />
                </div>

                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Assign Room Admin</label>
                  <select
                    name="room[admin_id]"
                    class="w-full bg-slate-900 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm"
                  >
                    <option value="">Select Room Admin...</option>
                    <%= for admin <- @room_admins do %>
                      <option value={admin.id}>{admin.username}</option>
                    <% end %>
                  </select>
                </div>

                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Max Word Limit</label>
                  <.input
                    field={@room_form[:word_limit]}
                    type="number"
                    value="50"
                    class="w-full bg-slate-900 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm"
                  />
                </div>

                <div class="flex items-center justify-end gap-3 pt-2">
                  <button
                    type="button"
                    phx-click="close_create_room"
                    class="px-4 py-2 rounded-xl text-sm font-semibold bg-slate-700 text-slate-300 hover:bg-slate-600"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="px-4 py-2 rounded-xl text-sm font-semibold bg-amber-500 hover:bg-amber-600 text-white"
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
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm">
            <div class="bg-slate-800 border border-slate-700 rounded-3xl p-6 max-w-md w-full space-y-4 shadow-2xl relative">
              <button
                phx-click="close_create_admin"
                class="absolute top-4 right-4 text-slate-400 hover:text-white"
              >
                <.icon name="hero-x-mark" class="w-6 h-6" />
              </button>

              <h3 class="text-xl font-bold text-white">Add Room Administrator Account</h3>

              <.form :let={f} for={%{}} action="#" phx-submit="create_room_admin" class="space-y-4">
                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Username</label>
                  <.input
                    field={f[:username]}
                    name="admin[username]"
                    type="text"
                    required
                    class="w-full bg-slate-900 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm"
                  />
                </div>

                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Initial Password</label>
                  <.input
                    field={f[:password]}
                    name="admin[password]"
                    type="password"
                    required
                    class="w-full bg-slate-900 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm"
                  />
                </div>

                <div class="flex items-center justify-end gap-3 pt-2">
                  <button
                    type="button"
                    phx-click="close_create_admin"
                    class="px-4 py-2 rounded-xl text-sm font-semibold bg-slate-700 text-slate-300 hover:bg-slate-600"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="px-4 py-2 rounded-xl text-sm font-semibold bg-indigo-600 hover:bg-indigo-500 text-white"
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
