defmodule QaAppWeb.ModeratorLive.Show do
  use QaAppWeb, :live_view

  alias QaApp.Engagement
  alias QaApp.Events
  alias QaApp.RoomCapacity
  alias QaAppWeb.ModeratorLive.RoomAuth

  # How long an armed "close room" confirmation stays open before it
  # auto-cancels, protecting against an accidental close.
  @deactivate_confirm_timeout 6_000

  def mount(params, _session, socket) do
    case RoomAuth.authorize(socket, params) do
      {:ok, socket} ->
        {:ok,
         socket
         |> assign(:visitor_count, RoomCapacity.count(socket.assigns.room.id))
         |> assign(:show_qr_modal?, false)
         |> assign(:confirm_deactivate_id, nil)
         |> assign(:tab, :raised)
         |> load_questions()}

      {:redirect, socket} ->
        {:ok, socket}
    end
  end

  def handle_params(%{"tab" => "asked"}, _uri, socket) do
    {:noreply,
     socket |> assign(:tab, :asked) |> assign(:confirm_deactivate_id, nil) |> load_questions()}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket |> assign(:tab, :raised) |> assign(:confirm_deactivate_id, nil) |> load_questions()}
  end

  def handle_event("mark_asked", %{"id" => question_id}, socket) do
    set_asked(socket, question_id, true)
  end

  def handle_event("mark_unasked", %{"id" => question_id}, socket) do
    set_asked(socket, question_id, false)
  end

  def handle_event("toggle_qr_modal", _, socket) do
    {:noreply, assign(socket, :show_qr_modal?, not socket.assigns.show_qr_modal?)}
  end

  # Opening a room is a single click (the banner CTA); closing arms a
  # confirmation so a moderator can't accidentally hide questions from
  # visitors mid-moderation.
  def handle_event("toggle_room_active", %{"id" => id}, socket) do
    room = socket.assigns.room

    if room.id == id && room.is_active do
      Process.send_after(self(), :reset_room_confirm, @deactivate_confirm_timeout)
      {:noreply, assign(socket, :confirm_deactivate_id, room.id)}
    else
      case update_room_status(socket, room, true) do
        {:ok, socket} -> {:noreply, socket}
        {:error, socket} -> {:noreply, socket}
      end
    end
  end

  def handle_event("confirm_room_inactive", %{"id" => id}, socket) do
    room = socket.assigns.room

    if room.id == id && room.is_active do
      case update_room_status(socket, room, false) do
        {:ok, socket} -> {:noreply, socket}
        {:error, socket} -> {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :confirm_deactivate_id, nil)}
    end
  end

  def handle_event("cancel_room_inactive", %{"id" => id}, socket) do
    socket =
      if socket.assigns[:confirm_deactivate_id] == id do
        assign(socket, :confirm_deactivate_id, nil)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({tag, _question}, socket) when tag in [:question_created, :question_updated] do
    {:noreply, load_questions(socket)}
  end

  def handle_info({:room_settings_updated, room}, socket) do
    {:noreply,
     socket
     |> assign(:room, room)
     |> assign(:confirm_deactivate_id, nil)}
  end

  # Visitor presence changed (join/leave); refresh the live count.
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :visitor_count, RoomCapacity.count(socket.assigns.room.id))}
  end

  # Moderators are not visitors, so expulsions do not apply to this view.
  def handle_info({:room_visitors_expelled, _session_ids}, socket) do
    {:noreply, socket}
  end

  # The armed "close room" confirmation timed out; cancel it so an accidental
  # close can't happen after the moderator walked away.
  def handle_info(:reset_room_confirm, socket) do
    {:noreply, assign(socket, :confirm_deactivate_id, nil)}
  end

  defp update_room_status(socket, room, is_active) do
    case Events.update_room(room, %{"is_active" => is_active}) do
      {:ok, updated_room} ->
        {:ok,
         socket
         |> assign(:room, updated_room)
         |> assign(:confirm_deactivate_id, nil)}

      {:error, changeset} ->
        errors = Enum.map_join(changeset.errors, ", ", fn {key, {msg, _}} -> "#{key} #{msg}" end)

        {:error,
         socket
         |> assign(:confirm_deactivate_id, nil)
         |> put_flash(:error, "Failed to update room status: #{errors}")}
    end
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
              <span
                id="moderator-room-status"
                class="inline-flex items-center gap-1.5 h-10 px-3 rounded border border-line-strong bg-transparent font-mono text-[11px] uppercase tracking-[0.14em] tabular-nums"
              >
                <span class={[
                  "w-1.5 h-1.5 rounded-full",
                  if(@room.is_active, do: "bg-accent motion-safe:animate-pulse", else: "bg-ink/50")
                ]}></span>
                <span class={if(@room.is_active, do: "text-ink-2", else: "text-ink-3")}>
                  <%= if @room.is_active do %>
                    Open
                  <% else %>
                    Not open
                  <% end %>
                </span>
              </span>

              <button
                :if={@room.is_active && @confirm_deactivate_id != @room.id}
                id="close-room-trigger"
                phx-click="toggle_room_active"
                phx-value-id={@room.id}
                class="inline-flex items-center gap-1.5 h-10 px-3 rounded text-[13px] font-medium text-ink-3 hover:text-ink hover:bg-surface transition-colors duration-150"
              >
                <.icon name="hero-lock-closed" class="size-4" /> Close room
              </button>

              <span
                id="moderator-visitor-count"
                class="hidden sm:inline-flex items-center gap-1.5 h-10 px-3 rounded border border-line-strong bg-transparent font-mono text-[11px] uppercase tracking-[0.14em] text-ink-2 tabular-nums"
              >
                <span class="w-1.5 h-1.5 rounded-full bg-accent"></span>
                {@visitor_count}
                <span class="normal-case">live</span>
                <%= if @room.max_visitors do %>
                  <span class="text-ink-3">/ {@room.max_visitors}</span>
                <% end %>
              </span>

              <button
                phx-click="toggle_qr_modal"
                class="inline-flex items-center gap-2 h-10 px-4 rounded border border-line-strong bg-transparent text-ink text-sm font-medium hover:border-ink transition-colors duration-150"
              >
                <.icon name="hero-qr-code" class="size-4" /> Share QR Code
              </button>
            </div>
          </div>
        </header>

        <%= if !@room.is_active do %>
          <div
            id="room-not-open-banner"
            class="mt-6 flex flex-col sm:flex-row sm:items-center justify-between gap-3 rounded border border-line-strong px-4 py-3"
          >
            <div class="flex items-center gap-3 min-w-0">
              <span class="w-2 h-2 rounded-full bg-ink/50 shrink-0"></span>
              <div class="min-w-0">
                <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-2">
                  Room is not open
                </p>
                <p class="mt-0.5 text-[13px] text-ink-3">
                  Visitors see a waiting page and can't submit questions until you open the room.
                </p>
              </div>
            </div>
            <button
              id="open-room-button"
              phx-click="toggle_room_active"
              phx-value-id={@room.id}
              class="inline-flex items-center justify-center gap-2 h-10 px-4 rounded bg-ink text-paper text-sm font-medium hover:bg-accent transition-colors duration-150 shrink-0"
            >
              <.icon name="hero-play" class="size-3.5" /> Open room
            </button>
          </div>
        <% end %>

        <%= if @confirm_deactivate_id == @room.id do %>
          <div class="mt-6">
            <.deactivate_confirm room={@room} id_prefix="questions" variant="strip" />
          </div>
        <% end %>

        <Layouts.room_tabs room={@room} active={:questions} />

        <!-- Live Moderation Question Feed -->
        <section class="mt-10">
          <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1.5 pb-3 border-b border-line">
            <div id="moderator-tabs" class="flex items-center gap-1 sm:gap-2">
              <.link
                id="moderator-tab-raised"
                patch={~p"/moderator/r/#{@room.slug}?tab=raised"}
                class={[
                  "inline-flex items-center gap-2 h-9 px-3 sm:px-4 rounded transition-colors duration-150",
                  if(@tab == :raised,
                    do: "bg-ink text-paper",
                    else: "text-ink-3 hover:text-ink hover:bg-surface"
                  )
                ]}
              >
                <span class="font-mono text-[11px] uppercase tracking-[0.14em]">
                  Raised Questions
                </span>
                <span class={[
                  "font-mono text-[11px] tabular-nums",
                  if(@tab == :raised, do: "text-paper/60", else: "text-ink-3/60")
                ]}>
                  {@raised_count}
                </span>
              </.link>

              <.link
                id="moderator-tab-asked"
                patch={~p"/moderator/r/#{@room.slug}?tab=asked"}
                class={[
                  "inline-flex items-center gap-2 h-9 px-3 sm:px-4 rounded transition-colors duration-150",
                  if(@tab == :asked,
                    do: "bg-ink text-paper",
                    else: "text-ink-3 hover:text-ink hover:bg-surface"
                  )
                ]}
              >
                <span class="font-mono text-[11px] uppercase tracking-[0.14em]">
                  Asked Questions
                </span>
                <span class={[
                  "font-mono text-[11px] tabular-nums",
                  if(@tab == :asked, do: "text-paper/60", else: "text-ink-3/60")
                ]}>
                  {@asked_count}
                </span>
              </.link>
            </div>

            <span class="w-full sm:w-auto font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 tabular-nums">
              {if(@tab == :raised, do: @raised_count, else: @asked_count)} total · Sorted by votes
            </span>
          </div>

          <div id="moderator-questions-feed">
            <%= if @tab == :raised do %>
              <div id="raised-questions-feed" phx-update="stream">
                <div id="raised-empty" class="hidden only:block py-16 text-center">
                  <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                    No raised questions yet
                  </p>
                  <p class="mt-2 text-[13px] text-ink-3">
                    Questions submitted by the audience will appear here.
                  </p>
                </div>

                <.moderator_question
                  :for={{id, {question, index}} <- @streams.raised_questions}
                  id={id}
                  question={question}
                  index={index}
                />
              </div>
            <% else %>
              <div id="asked-questions-feed" phx-update="stream">
                <div id="asked-empty" class="hidden only:block py-16 text-center">
                  <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                    No asked questions yet
                  </p>
                  <p class="mt-2 text-[13px] text-ink-3">
                    Questions you mark as asked will appear here.
                  </p>
                </div>

                <.moderator_question
                  :for={{id, {question, index}} <- @streams.asked_questions}
                  id={id}
                  question={question}
                  index={index}
                  asked?
                />
              </div>
            <% end %>
          </div>
        </section>

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
                <img
                  src={~p"/moderator/r/#{@room.slug}/qr.png"}
                  alt="QR Code"
                  class="w-44 h-44 mx-auto"
                />
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

  defp set_asked(socket, question_id, is_asked) do
    case Engagement.set_question_asked(socket.assigns.room.id, question_id, is_asked) do
      {:ok, _updated_question} ->
        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to update question state.")}
    end
  end

  defp load_questions(socket) do
    room_id = socket.assigns.room.id
    raised = Engagement.list_active_questions(room_id)
    asked = Engagement.list_asked_questions(room_id)

    socket
    |> assign(:raised_count, length(raised))
    |> assign(:asked_count, length(asked))
    |> stream(:raised_questions, Enum.with_index(raised, 1),
      dom_id: fn {question, _index} -> "moderator-q-" <> question.id end,
      reset: true
    )
    |> stream(:asked_questions, Enum.with_index(asked, 1),
      dom_id: fn {question, _index} -> "moderator-q-" <> question.id end,
      reset: true
    )
  end
end
