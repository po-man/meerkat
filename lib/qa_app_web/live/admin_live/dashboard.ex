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

        <%= if Enum.empty?(@rooms) do %>
          <div class="py-16 text-center">
            <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
              No assigned rooms found
            </p>
            <p class="mt-2 text-[13px] leading-relaxed text-ink-3">
              Contact your Super Administrator to create or assign a room to your account.
            </p>
          </div>
        <% else %>
          <div>
            <%= for {room, i} <- Enum.with_index(@rooms) do %>
              <div class="group grid grid-cols-12 gap-x-4 sm:gap-x-6 items-center py-5 border-b border-line hover:bg-surface transition-colors">
                <div class="col-span-1 hidden sm:block">
                  <span class="font-mono text-xs text-ink-3 tabular-nums">{i + 1}</span>
                </div>

                <div class="col-span-11 sm:col-span-5 min-w-0">
                  <h3 class="text-[17px] font-semibold tracking-[-0.01em] text-ink truncate">
                    {room.title}
                  </h3>
                  <p class="mt-0.5 font-mono text-xs text-ink-3">/r/{room.slug}</p>
                </div>

                <div class="col-span-4 sm:col-span-2 flex sm:hidden">
                  <span class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-2 flex items-center gap-2">
                    <span class="w-1.5 h-1.5 rounded-full bg-accent"></span> Active
                  </span>
                </div>

                <div class="col-span-4 sm:col-span-2 hidden sm:flex">
                  <span class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-2 flex items-center gap-2">
                    <span class="w-1.5 h-1.5 rounded-full bg-accent"></span> Active
                  </span>
                </div>

                <div class="col-span-8 sm:col-span-3 flex items-center justify-end gap-5">
                  <.link
                    navigate={~p"/admin/r/#{room.slug}"}
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
            <% end %>
          </div>
        <% end %>
      </div>
    </QaAppWeb.Layouts.app>
    """
  end
end
