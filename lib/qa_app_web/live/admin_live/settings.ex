defmodule QaAppWeb.AdminLive.Settings do
  use QaAppWeb, :live_view

  alias QaApp.Events

  def mount(%{"slug" => slug}, _session, socket) do
    case Events.get_room_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Event room not found")
         |> redirect(to: "/")}

      room ->
        current_user = socket.assigns[:current_user]

        if current_user && (current_user.role == :super_admin || current_user.id == room.admin_id) do
          if connected?(socket) do
            Events.subscribe_room(room.id)
          end

          settings_form = to_form(Events.change_room(room))

          {:ok,
           socket
           |> assign(:room, room)
           |> assign(:settings_form, settings_form)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Unauthorized access to this room dashboard.")
           |> redirect(to: "/")}
        end
    end
  end

  def handle_event("save_settings", %{"room" => room_params}, socket) do
    room = socket.assigns.room

    case Events.update_room(room, room_params) do
      {:ok, updated_room} ->
        {:noreply,
         socket
         |> assign(:room, updated_room)
         |> assign(:settings_form, to_form(Events.change_room(updated_room)))
         |> put_flash(:info, "Room settings updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :settings_form, to_form(changeset))}
    end
  end

  def handle_info({:room_settings_updated, room}, socket) do
    {:noreply,
     socket
     |> assign(:room, room)
     |> assign(:settings_form, to_form(Events.change_room(room)))}
  end

  def render(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-6xl mx-auto px-6 pt-12 sm:pt-16 pb-24">
        <!-- Masthead -->
        <header class="border-b border-line pb-8">
          <div class="flex flex-col lg:flex-row lg:items-end lg:justify-between gap-6">
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
              <.link
                href={~p"/admin/r/#{@room.slug}/export.csv"}
                target="_blank"
                class="inline-flex items-center gap-2 h-10 px-4 rounded border border-line-strong bg-transparent text-ink text-sm font-medium hover:border-ink transition-colors duration-150"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV
              </.link>
            </div>
          </div>
        </header>

        <Layouts.room_tabs room={@room} active={:settings} />

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
              <.input field={@settings_form[:intro_text]} type="textarea" label="Intro Text" />
            </div>

            <div>
              <.input
                field={@settings_form[:word_limit]}
                type="number"
                label="Max Word Limit per Question"
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
