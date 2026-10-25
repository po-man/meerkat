defmodule QaAppWeb.AdminLive.Dashboard do
  use QaAppWeb, :live_view

  alias QaApp.Events

  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

    rooms =
      Events.list_rooms()
      |> Enum.filter(fn r -> r.admin_id == current_user.id end)

    {:ok, assign(socket, :rooms, rooms)}
  end

  def render(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-5xl mx-auto px-4 py-8 space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-extrabold text-white">Your Event Rooms</h1>
            <p class="text-sm text-slate-400 mt-1">
              Select an event room to moderate live questions.
            </p>
          </div>
        </div>

        <%= if Enum.empty?(@rooms) do %>
          <div class="bg-slate-800/40 rounded-2xl p-8 text-center border border-slate-700/40">
            <.icon name="hero-rectangle-stack" class="w-12 h-12 text-slate-500 mx-auto mb-3" />
            <p class="text-slate-300 font-semibold">No assigned rooms found.</p>
            <p class="text-xs text-slate-500 mt-1">
              Contact your Super Administrator to create or assign a room to your account.
            </p>
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <%= for room <- @rooms do %>
              <div class="bg-slate-800/80 backdrop-blur-md rounded-2xl p-6 border border-slate-700/60 shadow-xl space-y-4 hover:border-indigo-500/50 transition-all">
                <div class="flex items-start justify-between">
                  <div>
                    <h3 class="text-xl font-bold text-white">{room.title}</h3>
                    <p class="text-xs text-indigo-400 font-medium">/r/{room.slug}</p>
                  </div>
                  <span class="px-2.5 py-1 rounded-full text-xs font-semibold bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                    Active
                  </span>
                </div>

                <div class="flex items-center gap-3 pt-2">
                  <.link
                    navigate={~p"/admin/r/#{room.slug}"}
                    class="flex-1 text-center py-2.5 px-4 rounded-xl text-sm font-semibold text-white bg-indigo-600 hover:bg-indigo-500 transition-all shadow-md"
                  >
                    Open Dashboard
                  </.link>
                  <.link
                    href={~p"/r/#{room.slug}"}
                    target="_blank"
                    class="py-2.5 px-3 rounded-xl text-sm font-semibold bg-slate-700 text-slate-300 hover:bg-slate-600 transition-all border border-slate-600"
                  >
                    <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                  </.link>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </QaAppWeb.Layouts.app>
    """
  end
end
