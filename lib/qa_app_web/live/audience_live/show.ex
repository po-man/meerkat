defmodule QaAppWeb.AudienceLive.Show do
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
        if socket.assigns[:session_id] && connected?(socket) do
          Events.subscribe_room(room.id)
        end

        session_id = socket.assigns[:session_id]
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
         |> questions_stream()
         |> assign(:user_voted_ids, user_voted_ids)
         |> assign(:user_question, user_question)
         |> assign(:form, form)
         |> assign(:char_count, 0)
         |> assign(:submitted?, not is_nil(user_question))}
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
      {:ok, _res} ->
        user_voted_ids = Engagement.list_user_voted_question_ids(room.id, session_id)

        {:noreply,
         socket
         |> assign(:user_voted_ids, user_voted_ids)
         |> questions_stream()}

      {:error, :cannot_vote_own_question} ->
        {:noreply, put_flash(socket, :error, "You cannot upvote your own question.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:question_created, _question}, socket) do
    {:noreply, questions_stream(socket)}
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
     |> questions_stream()}
  end

  def handle_info({:room_settings_updated, room}, socket) do
    {:noreply, assign(socket, :room, room)}
  end

  defp own_question?(user_question, question),
    do: user_question && user_question.id == question.id

  defp questions_stream(socket) do
    socket.assigns.room.id
    |> Engagement.list_active_questions()
    |> Enum.with_index(1)
    |> then(fn entries ->
      socket
      |> assign(:questions_count, length(entries))
      |> stream(:questions, entries,
        dom_id: fn {question, _index} -> "q-" <> question.id end,
        reset: true
      )
    end)
  end

  def render(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash}>
      <div class="max-w-5xl mx-auto px-6 pt-12 sm:pt-16 pb-24">
        <!-- Masthead -->
        <header class="border-b border-line pb-10">
          <div class="grid grid-cols-12 gap-x-6 items-end">
            <div class="col-span-12 lg:col-span-8">
              <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 flex items-center gap-2.5">
                <span class="w-2 h-2 rounded-full bg-accent motion-safe:animate-pulse"></span>
                Live Event
              </p>

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

        <!-- Submission Form or Submitted Confirmation -->
        <section class="mt-12">
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
        <section class="mt-14">
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
