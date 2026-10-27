defmodule QaAppWeb.AdminLive.Show do
  use QaAppWeb, :live_view

  alias QaApp.Events
  alias QaApp.Engagement

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

          questions = Engagement.list_all_questions(room.id)
          settings_form = to_form(Events.change_room(room))

          {:ok,
           socket
           |> assign(:room, room)
           |> assign(:questions, questions)
           |> assign(:settings_form, settings_form)
           |> assign(:show_qr_modal?, false)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Unauthorized access to this room dashboard.")
           |> redirect(to: "/")}
        end
    end
  end

  def handle_event("mark_asked", %{"id" => question_id}, socket) do
    question = Engagement.get_question!(question_id)

    case Engagement.mark_as_asked(question) do
      {:ok, _updated_question} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update question state.")}
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

  def handle_event("toggle_qr_modal", _, socket) do
    {:noreply, assign(socket, :show_qr_modal?, not socket.assigns.show_qr_modal?)}
  end

  def handle_info({:question_created, _question}, socket) do
    questions = Engagement.list_all_questions(socket.assigns.room.id)
    {:noreply, assign(socket, :questions, questions)}
  end

  def handle_info({:question_updated, _question}, socket) do
    questions = Engagement.list_all_questions(socket.assigns.room.id)
    {:noreply, assign(socket, :questions, questions)}
  end

  def handle_info({:room_settings_updated, room}, socket) do
    {:noreply, assign(socket, :room, room)}
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
              <button
                phx-click="toggle_qr_modal"
                class="inline-flex items-center gap-2 h-10 px-4 rounded border border-line-strong bg-transparent text-ink text-sm font-medium hover:border-ink transition-colors duration-150"
              >
                <.icon name="hero-qr-code" class="size-4" /> Share QR Code
              </button>

              <.link
                href={~p"/admin/r/#{@room.slug}/export.csv"}
                target="_blank"
                class="inline-flex items-center gap-2 h-10 px-4 rounded bg-ink text-paper text-sm font-medium hover:bg-accent transition-colors duration-150"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV
              </.link>
            </div>
          </div>
        </header>

        <div class="grid grid-cols-12 gap-x-8 lg:gap-x-12 mt-10">
          <!-- Left Column: Room Settings Form -->
          <section class="col-span-12 lg:col-span-4 lg:border-r lg:border-line lg:pr-10">
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

          <!-- Right Column: Live Moderation Question Feed -->
          <section class="col-span-12 lg:col-span-8 mt-10 lg:mt-0">
            <div class="flex items-baseline justify-between gap-4 pb-3 border-b border-line">
              <h3 class="text-lg font-semibold tracking-[-0.01em] text-ink">
                Questions
              </h3>
              <span class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 tabular-nums">
                {length(@questions)} total · Sorted by votes
              </span>
            </div>

            <%= if Enum.empty?(@questions) do %>
              <div class="py-16 text-center">
                <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                  No questions submitted yet
                </p>
              </div>
            <% else %>
              <div id="admin-questions-feed">
                <%= for {question, i} <- Enum.with_index(@questions) do %>
                  <div
                    id={"admin-q-#{question.id}"}
                    class={[
                      "grid grid-cols-12 gap-x-4 sm:gap-x-6 items-start py-5 border-b border-line",
                      if(question.is_asked, do: "opacity-60")
                    ]}
                  >
                    <div class="col-span-2 sm:col-span-1">
                      <span class="font-mono text-xs text-ink-3 tabular-nums">{i + 1}</span>
                    </div>

                    <div class="col-span-10 sm:col-span-11 flex items-start gap-4">
                      <span class={[
                        "shrink-0 w-11 py-2 rounded border flex flex-col items-center justify-center gap-0.5 font-mono text-xs tabular-nums",
                        if(question.is_asked,
                          do: "border-line text-ink-3",
                          else: "border-line-strong text-ink"
                        )
                      ]}>
                        <.icon name="hero-chevron-up" class="size-3.5" />
                        {question.vote_count}
                      </span>

                      <div class="flex-1 min-w-0 pt-1">
                        <p class="text-[16px] leading-relaxed text-ink break-words">
                          {question.content}
                        </p>
                        <div class="mt-2 flex items-center gap-3 font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                          <span class="normal-case tracking-normal tabular-nums">
                            Submitted {Calendar.strftime(question.inserted_at, "%I:%M %p")}
                          </span>
                          <%= if question.is_asked do %>
                            <span class="text-ink-2 flex items-center gap-1.5">
                              <span class="w-1.5 h-1.5 rounded-full bg-accent"></span> Asked
                            </span>
                          <% end %>
                        </div>
                      </div>
                    </div>

                    <div class="col-span-12 sm:col-span-3 flex sm:justify-end pt-3 sm:pt-1">
                      <%= if not question.is_asked do %>
                        <button
                          phx-click="mark_asked"
                          phx-value-id={question.id}
                          class="inline-flex items-center gap-1.5 h-8 px-3 rounded border border-line-strong bg-transparent text-ink-2 text-xs font-medium hover:border-ink hover:text-ink transition-colors duration-150"
                        >
                          <.icon name="hero-check" class="size-3.5" /> Mark as Asked
                        </button>
                      <% else %>
                        <span class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                          Asked
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </section>
        </div>

        <!-- QR Code Sharing Modal -->
        <%= if @show_qr_modal? do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40">
            <div class="bg-paper border border-line-strong rounded-lg p-6 sm:p-8 max-w-sm w-full text-center relative">
              <button
                phx-click="toggle_qr_modal"
                aria-label="Close"
                class="absolute top-3 right-3 w-9 h-9 rounded border border-transparent hover:border-line-strong flex items-center justify-center text-ink-3 hover:text-ink transition-colors"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>

              <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                Audience QR Code
              </p>
              <h3 class="mt-3 text-xl font-semibold tracking-[-0.02em] text-ink">
                Join this room
              </h3>
              <p class="mt-1 font-mono text-xs text-ink-3 break-all">/r/{@room.slug}</p>

              <div class="mt-6 inline-block bg-white p-4 border border-line-strong rounded">
                <img src={~p"/admin/r/#{@room.slug}/qr.png"} alt="QR Code" class="w-44 h-44 mx-auto" />
              </div>

              <div class="mt-5">
                <a
                  href={~p"/r/#{@room.slug}"}
                  target="_blank"
                  class="text-[13px] font-medium text-ink underline-offset-4 hover:underline hover:text-accent transition-colors break-all"
                >
                  Open Audience Link →
                </a>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </QaAppWeb.Layouts.app>
    """
  end
end
