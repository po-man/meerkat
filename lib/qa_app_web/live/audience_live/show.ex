defmodule QaAppWeb.AudienceLive.Show do
  use QaAppWeb, :live_view

  alias QaApp.Events
  alias QaApp.Engagement
  alias QaApp.RoomCapacity

  # Presence diffs are coalesced into at most one recount per viewer per
  # window, so a room filling up does not multiply work by the visitor count.
  @visitor_count_debounce 250

  def mount(%{"slug" => slug}, _session, socket) do
    case Events.get_room_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Event room not found")
         |> redirect(to: "/")}

      room ->
        session_id = socket.assigns[:session_id]

        case RoomCapacity.join(socket, room, session_id) do
          :full ->
            {:ok,
             socket
             |> put_flash(:error, "This room is currently at full capacity.")
             |> redirect(to: ~p"/r/#{room.slug}/full")}

          :ok ->
            if connected?(socket) do
              Events.subscribe_room(room.id)
              Events.subscribe_room_presence(room.id)
              Events.subscribe_room_settings(room.id)
            end

            visitor_count = RoomCapacity.count(room.id)
            user_voted_ids = Engagement.list_user_voted_question_ids(room.id, session_id)
            user_question = Engagement.get_question_by_session(room.id, session_id)

            form =
              if user_question do
                nil
              else
                Engagement.change_question(room, session_id, %{"content" => ""})
                |> to_form()
              end

            {:ok,
             socket
             |> assign(:room, room)
             |> assign(:visitor_count, visitor_count)
             |> questions_stream()
             |> assign(:user_voted_ids, user_voted_ids)
             |> assign(:user_question, user_question)
             |> assign(:form, form)
             |> assign(:char_count, 0)
             |> assign(:visitor_count_timer, nil)
             |> assign(:submitted?, not is_nil(user_question))}
        end
    end
  end

  def handle_event("validate_question", params, socket) do
    content = params["content"] || get_in(params, ["question", "content"]) || ""
    room = socket.assigns.room
    char_count = String.length(content)

    changeset =
      socket.assigns.session_id
      |> then(&Engagement.change_question(room, &1, %{"content" => content}))
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:char_count, char_count)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("submit_question", params, socket) do
    content = params["content"] || get_in(params, ["question", "content"]) || ""
    room = socket.assigns.room
    session_id = socket.assigns.session_id

    case Engagement.create_question(room, session_id, %{"content" => content}) do
      {:ok, question} ->
        {:noreply,
         socket
         |> assign(:user_question, question)
         |> assign(:submitted?, true)
         |> assign(:form, nil)
         |> questions_stream()
         |> put_flash(:info, "Question submitted successfully!")}

      {:error, %Ecto.Changeset{} = changeset} ->
        char_count = String.length(content)

        {:noreply,
         socket
         |> assign(:char_count, char_count)
         |> assign(:form, to_form(changeset))}
    end
  end

  def handle_event("toggle_vote", %{"id" => question_id}, socket) do
    session_id = socket.assigns.session_id
    room = socket.assigns.room

    case Engagement.toggle_vote(room.id, question_id, session_id) do
      {:ok, {direction, question}} ->
        # The vote store buffers the vote in memory and broadcasts the new
        # counts in batches, so this click costs no database round trip. Keep
        # this visitor's own selection in sync locally.
        #
        # The button lives inside a streamed row, so the row must be re-streamed
        # for the selection to render immediately; an assign change alone does
        # not re-render stream children.
        {:noreply,
         socket
         |> assign(
           :user_voted_ids,
           put_user_vote(socket.assigns.user_voted_ids, question_id, direction)
         )
         |> update_question_stream(question)}

      {:error, :cannot_vote_own_question} ->
        {:noreply, put_flash(socket, :error, "You cannot upvote your own question.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:question_created, question}, socket) do
    # The broadcast already carries the whole question, so insert it into the
    # local feed instead of re-querying it once per connected viewer.
    {:noreply, insert_question_stream(socket, question)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, schedule_visitor_count_refresh(socket)}
  end

  def handle_info(:refresh_visitor_count, socket) do
    {:noreply,
     socket
     |> assign(:visitor_count, RoomCapacity.count(socket.assigns.room.id))
     |> assign(:visitor_count_timer, nil)}
  end

  def handle_info({:room_visitors_expelled, session_ids}, socket) do
    if socket.assigns[:session_id] in session_ids do
      {:noreply,
       socket
       |> put_flash(:error, "This room is now at full capacity.")
       |> redirect(to: ~p"/r/#{socket.assigns.room.slug}/full")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:question_updated, question}, socket) do
    user_question =
      if socket.assigns.user_question && socket.assigns.user_question.id == question.id do
        question
      else
        socket.assigns.user_question
      end

    {:noreply,
     socket
     |> assign(:user_question, user_question)
     |> update_question_stream(question)}
  end

  def handle_info({:questions_updated, questions}, socket) do
    {:noreply, apply_questions_updated(socket, questions)}
  end

  def handle_info({:room_settings_updated, room}, socket) do
    socket = assign(socket, :room, room)

    # When the room flips back to active, re-stream the questions so the feed
    # reflects anything that happened while visitors were on the not-ready view.
    if room.is_active do
      {:noreply, questions_stream(socket)}
    else
      {:noreply, socket}
    end
  end

  defp own_question?(user_question, question),
    do: user_question && user_question.id == question.id

  defp questions_stream(socket) do
    entries =
      socket.assigns.room.id
      |> Engagement.list_active_questions()
      |> Enum.with_index(1)

    put_questions_stream(socket, entries)
  end

  defp put_questions_stream(socket, entries) do
    socket
    |> assign(:questions_count, length(entries))
    |> assign(:question_entries, entries)
    |> stream(:questions, entries, dom_id: &question_dom_id/1, reset: true)
  end

  defp question_dom_id({question, _index}), do: "q-" <> question.id

  # Votes are broadcast to every connected visitor, so re-querying the whole
  # feed here would mean one database query per viewer per vote. Instead, keep
  # the in-memory feed sorted and only reset the stream when a vote changes the
  # order; otherwise patch just the row that changed.
  defp update_question_stream(socket, question) do
    entries = socket.assigns.question_entries

    if question.is_asked do
      entries = Enum.reject(entries, fn {entry, _index} -> entry.id == question.id end)

      socket
      |> assign(:questions_count, length(entries))
      |> assign(:question_entries, entries)
      |> stream_delete(:questions, {question, nil})
    else
      remaining = Enum.reject(entries, fn {entry, _index} -> entry.id == question.id end)
      new_entries = sort_question_entries(remaining ++ [{question, nil}])

      if question_ids(entries) == question_ids(new_entries) do
        {updated, index} =
          Enum.find(new_entries, fn {entry, _index} -> entry.id == question.id end)

        socket
        |> assign(:question_entries, new_entries)
        |> stream_insert(:questions, {updated, index})
      else
        put_questions_stream(socket, new_entries)
      end
    end
  end

  # A coalesced batch of vote changes from the vote store. Apply them all
  # before touching the stream, so a burst of votes costs at most one re-sort
  # and one stream reset per viewer.
  defp apply_questions_updated(socket, questions) do
    entries = socket.assigns.question_entries
    by_id = Map.new(questions, &{&1.id, &1})

    updated =
      entries
      |> Enum.map(fn {question, _index} -> {Map.get(by_id, question.id, question), nil} end)
      |> Enum.reject(fn {question, _index} -> question.is_asked end)

    present_ids = MapSet.new(updated, fn {question, _index} -> question.id end)

    additions =
      for {id, question} <- by_id,
          not question.is_asked,
          not MapSet.member?(present_ids, id),
          do: {question, nil}

    new_entries = sort_question_entries(updated ++ additions)

    socket =
      assign(
        socket,
        :user_question,
        updated_user_question(socket.assigns.user_question, by_id)
      )

    if question_ids(entries) == question_ids(new_entries) do
      changed_ids = MapSet.new(questions, & &1.id)

      socket
      |> assign(:questions_count, length(new_entries))
      |> assign(:question_entries, new_entries)
      |> then(fn socket ->
        Enum.reduce(new_entries, socket, fn {question, _index} = entry, socket ->
          if MapSet.member?(changed_ids, question.id) do
            stream_insert(socket, :questions, entry)
          else
            socket
          end
        end)
      end)
    else
      put_questions_stream(socket, new_entries)
    end
  end

  defp updated_user_question(nil, _by_id), do: nil

  defp updated_user_question(%{id: id} = question, by_id) do
    Map.get(by_id, id, question)
  end

  # A newly created question has the lowest possible vote count and the newest
  # timestamp, so the vote-ordered feed almost always appends it at the end.
  # Patch that row in instead of resetting (or re-querying) the whole feed for
  # every connected viewer.
  defp insert_question_stream(socket, question) do
    entries = socket.assigns.question_entries

    if Enum.any?(entries, fn {entry, _index} -> entry.id == question.id end) do
      update_question_stream(socket, question)
    else
      new_entries = sort_question_entries(entries ++ [{question, nil}])

      if question_ids(new_entries) == question_ids(entries) ++ [question.id] do
        {inserted, index} =
          Enum.find(new_entries, fn {entry, _index} -> entry.id == question.id end)

        socket
        |> assign(:questions_count, length(new_entries))
        |> assign(:question_entries, new_entries)
        |> stream_insert(:questions, {inserted, index})
      else
        put_questions_stream(socket, new_entries)
      end
    end
  end

  defp put_user_vote(ids, question_id, :voted), do: MapSet.put(ids, question_id)
  defp put_user_vote(ids, question_id, :unvoted), do: MapSet.delete(ids, question_id)

  # Joins and leaves arrive in bursts (e.g. a hall filling up), and every
  # viewer subscribed to the room receives each diff. Coalesce them into one
  # presence recount per debounce window instead of one per diff.
  defp schedule_visitor_count_refresh(%{assigns: %{visitor_count_timer: nil}} = socket) do
    timer = Process.send_after(self(), :refresh_visitor_count, @visitor_count_debounce)
    assign(socket, :visitor_count_timer, timer)
  end

  defp schedule_visitor_count_refresh(socket), do: socket

  # Mirrors the SQL order used by `Engagement.list_active_questions/1`: most
  # votes first, then most recently submitted first. `Enum.sort_by/3` compares
  # sort keys as terms, so timestamps are converted to integers.
  defp sort_question_entries(entries) do
    entries
    |> Enum.map(fn {question, _index} -> question end)
    |> Enum.sort_by(
      fn question -> {question.vote_count, DateTime.to_unix(question.inserted_at)} end,
      :desc
    )
    |> Enum.with_index(1)
  end

  defp question_ids(entries), do: Enum.map(entries, fn {question, _index} -> question.id end)

  def render(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash}>
      <div class="max-w-5xl mx-auto px-6 pt-12 sm:pt-16 pb-24">
        <!-- Masthead -->
        <header class="border-b border-line pb-10">
          <div class="grid grid-cols-12 gap-x-6 items-end">
            <div class="col-span-12 lg:col-span-8">
              <div class="flex flex-wrap items-center gap-x-5 gap-y-1.5">
                <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 flex items-center gap-2.5">
                  <span class="w-2 h-2 rounded-full bg-accent motion-safe:animate-pulse"></span>
                  Live Event
                </p>

                <span
                  id="visitor-count"
                  class="inline-flex items-center gap-1.5 font-mono text-[11px] uppercase tracking-[0.14em] text-ink-2 tabular-nums"
                >
                  <span class="w-1.5 h-1.5 rounded-full bg-accent/70"></span>
                  {@visitor_count} attending
                </span>
              </div>

              <h1 class="mt-4 text-4xl sm:text-5xl font-semibold tracking-[-0.035em] leading-[1.03] text-ink">
                {@room.title}
              </h1>

              <%= if @room.intro_text do %>
                <p class="mt-4 text-[15px] leading-relaxed text-ink-2 max-w-xl">
                  {@room.intro_text}
                </p>
              <% end %>
            </div>
          </div>
        </header>

        <!-- Not Ready (inactive room) -->
        <section :if={!@room.is_active} id="room-not-ready" class="mt-12 max-w-2xl">
          <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 flex items-center gap-2.5">
            <span class="w-2 h-2 rounded-full bg-accent motion-safe:animate-pulse"></span>
            Room Not Ready
          </p>

          <h2 class="mt-4 text-2xl sm:text-3xl font-semibold tracking-[-0.03em] leading-[1.08] text-ink">
            This room isn't open yet
          </h2>

          <p class="mt-3 max-w-md text-[15px] leading-relaxed text-ink-2">
            {@room.title} hasn't started yet. This page stays open and will bring
            you in automatically as soon as the room is ready.
          </p>

          <div class="mt-6 inline-flex items-center gap-2.5 rounded border border-line-strong px-4 py-3">
            <span class="w-1.5 h-1.5 rounded-full bg-accent motion-safe:animate-pulse"></span>
            <span class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-2 tabular-nums">
              {@visitor_count} waiting
            </span>
          </div>
        </section>

        <!-- Submission Form or Submitted Confirmation -->
        <section :if={@room.is_active} class="mt-12">
          <%= if @submitted? do %>
            <div class="max-w-2xl">
              <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 flex items-center gap-2.5">
                <span class="w-2 h-2 bg-accent"></span> Question Submitted
              </p>

              <blockquote class="mt-5 border-l-2 border-ink pl-5 text-[19px] leading-relaxed tracking-[-0.01em] text-ink">
                “{@user_question.content}”
              </blockquote>

              <div class="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2">
                <span
                  id="user-question-status"
                  class="inline-flex items-center gap-1.5 font-mono text-[11px] uppercase tracking-[0.14em] text-ink-2"
                >
                  <span class={[
                    "w-1.5 h-1.5 rounded-full",
                    if(@user_question.is_asked, do: "bg-accent", else: "bg-ink")
                  ]}></span>
                  <%= if @user_question.is_asked do %>
                    Asked
                  <% else %>
                    Raised
                  <% end %>
                </span>

                <span class="text-ink-3/40">·</span>

                <span
                  id="user-question-vote-count"
                  class="inline-flex items-center gap-1.5 font-mono text-[11px] uppercase tracking-[0.14em] text-ink-2"
                >
                  <.icon name="hero-chevron-up" class="size-3.5" />
                  <span class="tabular-nums">{@user_question.vote_count}</span>
                  <span class="normal-case">
                    <%= if @user_question.vote_count == 1 do %>
                      upvote
                    <% else %>
                      upvotes
                    <% end %>
                  </span>
                </span>
              </div>

              <p class="mt-4 text-[13px] leading-relaxed text-ink-3">
                You can ask 1 question per event. You can still upvote questions asked by others
                below.
              </p>
            </div>
          <% else %>
            <div class="max-w-2xl">
              <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                Ask a Question Anonymously
              </p>

              <.form
                for={@form}
                id="question-form"
                phx-change="validate_question"
                phx-submit="submit_question"
                class="mt-5"
              >
                <.input
                  id="question-content-input"
                  name={@form[:content].name}
                  value={@form[:content].value}
                  type="textarea"
                  placeholder="What would you like to ask?"
                  maxlength={@room.char_limit}
                  class="w-full bg-transparent border-0 border-b border-line-strong rounded-none px-0 pt-2 pb-3 text-[17px] leading-relaxed text-ink placeholder:text-ink-3 resize-none h-28 focus:border-ink focus:outline-none transition-colors"
                />

                <div class="mt-4 flex items-center justify-between gap-4">
                  <div class="flex items-center gap-4">
                    <span class={[
                      "font-mono text-xs tabular-nums",
                      if(@char_count > @room.char_limit,
                        do: "text-danger",
                        else: "text-ink-3"
                      )
                    ]}>
                      {@char_count} / {@room.char_limit}
                      <span class="normal-case">characters</span>
                    </span>
                    <span class="hidden sm:block font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                      Anonymous submission
                    </span>
                  </div>

                  <button
                    type="submit"
                    disabled={@char_count > @room.char_limit}
                    class="inline-flex items-center gap-2 h-10 px-5 rounded bg-ink text-paper text-sm font-medium hover:bg-accent transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed disabled:pointer-events-none"
                  >
                    Submit <.icon name="hero-arrow-up-right" class="size-3.5" />
                  </button>
                </div>
              </.form>
            </div>
          <% end %>
        </section>

        <!-- Live Audience Questions Feed -->
        <section :if={@room.is_active} class="mt-14">
          <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1.5 pb-3 border-b border-line">
            <h2 class="text-lg font-semibold tracking-[-0.01em] text-ink">
              Audience Questions
            </h2>
            <span class="w-full sm:w-auto font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 tabular-nums">
              {@questions_count} open · Sorted by votes
            </span>
          </div>

          <div id="questions-feed" phx-update="stream">
            <div id="questions-empty" class="hidden only:block py-16 text-center">
              <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                No questions asked yet
              </p>
              <p class="mt-2 text-[13px] text-ink-3">Be the first to submit a question.</p>
            </div>

            <div
              :for={{id, {question, index}} <- @streams.questions}
              id={id}
              class={[
                "grid grid-cols-12 gap-x-4 sm:gap-x-6 items-start py-6 border-b border-line",
                own_question?(@user_question, question) &&
                  "bg-surface -mx-2 sm:-mx-3 px-2 sm:px-3 rounded-lg"
              ]}
            >
              <div class="col-span-1 sm:col-span-1">
                <span class={[
                  "hidden sm:block font-mono text-xs tabular-nums",
                  if(own_question?(@user_question, question),
                    do: "text-accent",
                    else: "text-ink-3"
                  )
                ]}>
                  {index}
                </span>
              </div>

              <div class="col-span-10 sm:col-span-11 flex items-start gap-4">
                <%= if own_question?(@user_question, question) do %>
                  <span
                    aria-label="Upvote count for your question"
                    class="shrink-0 w-11 h-11 rounded border border-line-strong bg-transparent text-ink-3 flex flex-col items-center justify-center gap-0.5"
                  >
                    <.icon name="hero-chevron-up" class="size-4" />
                    <span class="font-mono text-xs leading-none tabular-nums">
                      {question.vote_count}
                    </span>
                  </span>
                <% else %>
                  <button
                    phx-click="toggle_vote"
                    phx-value-id={question.id}
                    aria-label="Upvote question"
                    class={[
                      "shrink-0 w-11 h-11 rounded border flex flex-col items-center justify-center gap-0.5 transition-colors duration-150",
                      if(MapSet.member?(@user_voted_ids, question.id),
                        do: "bg-ink border-ink text-paper",
                        else: "border-line-strong text-ink-2 hover:border-ink hover:text-ink"
                      )
                    ]}
                  >
                    <.icon name="hero-chevron-up" class="size-4" />
                    <span class="font-mono text-xs leading-none tabular-nums">
                      {question.vote_count}
                    </span>
                  </button>
                <% end %>

                <div class="flex-1 min-w-0 pt-0.5">
                  <p class="text-[17px] leading-relaxed text-ink break-words">
                    {question.content}
                  </p>
                  <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
                    <span>Anonymous</span>
                    <span class="text-ink-3/40">·</span>
                    <.local_datetime
                      id={"question-time-#{question.id}"}
                      datetime={question.inserted_at}
                      format={:time}
                      class="normal-case tracking-normal tabular-nums"
                    />

                    <%= if own_question?(@user_question, question) do %>
                      <span class="text-ink-3/40">·</span>
                      <span
                        id={"your-question-#{question.id}"}
                        class="inline-flex items-center gap-1.5 text-accent"
                      >
                        <span class="w-1.5 h-1.5 rounded-full bg-accent"></span> Your question
                      </span>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>
    </QaAppWeb.Layouts.app>
    """
  end
end
