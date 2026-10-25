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
      <div class="max-w-6xl mx-auto px-4 py-6 space-y-6">
        <!-- Top Admin Banner -->
        <div class="bg-slate-800/80 backdrop-blur-md rounded-2xl p-6 border border-indigo-500/30 shadow-xl flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div class="flex items-center gap-2 mb-1">
              <span class="px-2.5 py-0.5 rounded-md text-xs font-bold bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                Moderator Dashboard
              </span>
              <span class="text-xs text-slate-400">Slug: /r/{@room.slug}</span>
            </div>
            <h1 class="text-2xl font-bold text-white">{@room.title}</h1>
          </div>

          <div class="flex items-center gap-3">
            <button
              phx-click="toggle_qr_modal"
              class="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-semibold bg-slate-700/80 text-white hover:bg-slate-600 transition-all border border-slate-600"
            >
              <.icon name="hero-qr-code" class="w-4 h-4" /> Share QR Code
            </button>

            <.link
              href={~p"/admin/r/#{@room.slug}/export.csv"}
              target="_blank"
              class="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-semibold bg-emerald-600 text-white hover:bg-emerald-500 transition-all shadow-lg shadow-emerald-600/20"
            >
              <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Export CSV
            </.link>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Left Column: Room Settings Form -->
          <div class="lg:col-span-1 bg-slate-800/80 backdrop-blur-md rounded-2xl p-6 border border-slate-700/60 shadow-xl space-y-4">
            <h3 class="text-lg font-bold text-white flex items-center gap-2">
              <.icon name="hero-cog-6-tooth" class="w-5 h-5 text-indigo-400" /> Event Settings
            </h3>

            <.form
              for={@settings_form}
              id="settings-form"
              phx-submit="save_settings"
              class="space-y-4"
            >
              <div>
                <label class="block text-xs font-medium text-slate-300 mb-1">Event Title</label>
                <.input
                  field={@settings_form[:title]}
                  type="text"
                  class="w-full bg-slate-900/90 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-slate-300 mb-1">Intro Text</label>
                <.input
                  field={@settings_form[:intro_text]}
                  type="textarea"
                  class="w-full bg-slate-900/90 border-slate-700 text-white rounded-xl p-3.5 text-sm h-24 resize-none"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-slate-300 mb-1">Max Word Limit per Question</label>
                <.input
                  field={@settings_form[:word_limit]}
                  type="number"
                  class="w-full bg-slate-900/90 border-slate-700 text-white rounded-xl px-3.5 py-2 text-sm"
                />
              </div>

              <button
                type="submit"
                class="w-full py-2.5 px-4 rounded-xl text-sm font-semibold text-white bg-indigo-600 hover:bg-indigo-500 transition-all shadow-md"
              >
                Save Settings
              </button>
            </.form>
          </div>

          <!-- Right Column: Live Moderation Question Feed -->
          <div class="lg:col-span-2 space-y-4">
            <div class="flex items-center justify-between px-1">
              <h3 class="text-lg font-bold text-white flex items-center gap-2">
                <.icon name="hero-queue-list" class="w-5 h-5 text-indigo-400" />
                Questions ({length(@questions)})
              </h3>
            </div>

            <%= if Enum.empty?(@questions) do %>
              <div class="bg-slate-800/40 rounded-2xl p-8 text-center border border-slate-700/40">
                <p class="text-slate-400 font-medium">No questions submitted yet.</p>
              </div>
            <% else %>
              <div id="admin-questions-feed" class="space-y-3">
                <%= for question <- @questions do %>
                  <div
                    id={"admin-q-#{question.id}"}
                    class={[
                      "rounded-2xl p-5 border shadow-lg flex items-start justify-between gap-4 transition-all duration-200",
                      if(question.is_asked,
                        do: "bg-slate-900/40 border-slate-800/60 opacity-60",
                        else: "bg-slate-800/80 backdrop-blur-md border-slate-700/60"
                      )
                    ]}
                  >
                    <div class="flex items-start gap-3 flex-1 min-w-0">
                      <div class="bg-indigo-600/20 text-indigo-300 border border-indigo-500/30 px-3 py-1.5 rounded-xl font-bold text-sm min-w-[48px] text-center">
                        ▲ {question.vote_count}
                      </div>

                      <div class="flex-1 min-w-0">
                        <p class="text-slate-100 text-base leading-relaxed break-words">
                          {question.content}
                        </p>
                        <div class="mt-2 flex items-center gap-3 text-xs text-slate-400">
                          <span>Submitted {Calendar.strftime(question.inserted_at, "%I:%M %p")}</span>
                          <%= if question.is_asked do %>
                            <span class="text-emerald-400 font-bold">• Answered / Asked</span>
                          <% end %>
                        </div>
                      </div>
                    </div>

                    <div>
                      <%= if not question.is_asked do %>
                        <button
                          phx-click="mark_asked"
                          phx-value-id={question.id}
                          class="px-3.5 py-1.5 rounded-xl text-xs font-semibold bg-emerald-600/20 text-emerald-300 hover:bg-emerald-600/30 border border-emerald-500/30 transition-all flex items-center gap-1.5"
                        >
                          <.icon name="hero-check" class="w-4 h-4" /> Mark as Asked
                        </button>
                      <% else %>
                        <span class="text-xs text-slate-500 font-medium px-2 py-1">Asked</span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <!-- QR Code Sharing Modal -->
        <%= if @show_qr_modal? do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm">
            <div class="bg-slate-800 border border-slate-700 rounded-3xl p-6 max-w-sm w-full text-center space-y-4 shadow-2xl relative">
              <button
                phx-click="toggle_qr_modal"
                class="absolute top-4 right-4 text-slate-400 hover:text-white"
              >
                <.icon name="hero-x-mark" class="w-6 h-6" />
              </button>

              <h3 class="text-xl font-bold text-white">Audience QR Code</h3>
              <p class="text-xs text-slate-400">Scan to open live room: /r/{@room.slug}</p>

              <div class="bg-white p-4 rounded-2xl inline-block border border-slate-200">
                <img src={~p"/admin/r/#{@room.slug}/qr.png"} alt="QR Code" class="w-48 h-48 mx-auto" />
              </div>

              <div>
                <a
                  href={~p"/r/#{@room.slug}"}
                  target="_blank"
                  class="text-xs text-indigo-400 hover:underline break-all"
                >
                  Open Audience Link
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
