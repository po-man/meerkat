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
        questions = Engagement.list_active_questions(room.id)
        user_voted_ids = Engagement.list_user_voted_question_ids(room.id, session_id)
        user_question = Engagement.get_question_by_session(room.id, session_id)

        form =
          if user_question do
            nil
          else
            to_form(%{"content" => ""})
          end

        {:ok,
         socket
         |> assign(:room, room)
         |> assign(:questions, questions)
         |> assign(:user_voted_ids, user_voted_ids)
         |> assign(:user_question, user_question)
         |> assign(:form, form)
         |> assign(:word_count, 0)
         |> assign(:submitted?, not is_nil(user_question))}
    end
  end

  def handle_event("validate_question", params, socket) do
    content = params["content"] || get_in(params, ["question", "content"]) || ""
    room = socket.assigns.room
    words = content |> String.trim() |> String.split(~r/\s+/, trim: true)
    word_count = if content == "", do: 0, else: length(words)

    changeset =
      %QaApp.Engagement.Question{room_id: room.id, session_id: socket.assigns.session_id}
      |> QaApp.Engagement.Question.changeset(%{"content" => content}, room.word_limit)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:word_count, word_count)
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
         |> put_flash(:info, "Question submitted successfully!")}

      {:error, %Ecto.Changeset{} = changeset} ->
        words = content |> String.trim() |> String.split(~r/\s+/, trim: true)
        word_count = if content == "", do: 0, else: length(words)

        {:noreply,
         socket
         |> assign(:word_count, word_count)
         |> assign(:form, to_form(changeset))}
    end
  end

  def handle_event("toggle_vote", %{"id" => question_id}, socket) do
    session_id = socket.assigns.session_id
    room = socket.assigns.room

    case Engagement.toggle_vote(question_id, session_id) do
      {:ok, _res} ->
        user_voted_ids = Engagement.list_user_voted_question_ids(room.id, session_id)
        {:noreply, assign(socket, :user_voted_ids, user_voted_ids)}

      {:error, :cannot_vote_own_question} ->
        {:noreply, put_flash(socket, :error, "You cannot upvote your own question.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:question_created, _question}, socket) do
    room = socket.assigns.room
    questions = Engagement.list_active_questions(room.id)
    {:noreply, assign(socket, :questions, questions)}
  end

  def handle_info({:question_updated, _question}, socket) do
    room = socket.assigns.room
    questions = Engagement.list_active_questions(room.id)
    {:noreply, assign(socket, :questions, questions)}
  end

  def handle_info({:room_settings_updated, room}, socket) do
    {:noreply, assign(socket, :room, room)}
  end

  def render(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash}>
      <div class="max-w-3xl mx-auto px-4 py-6 space-y-6">
        <!-- Event Header Card -->
        <div class="bg-slate-800/80 backdrop-blur-md rounded-2xl p-6 border border-slate-700/60 shadow-xl">
          <div class="flex items-center justify-between gap-4">
            <div>
              <span class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 mb-2">
                <span class="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span> Live Event
              </span>
              <h1 class="text-2xl sm:text-3xl font-bold text-white tracking-tight">{@room.title}</h1>
            </div>
            <div class="text-right">
              <span class="text-xs text-slate-400 uppercase tracking-wider block">Word Limit</span>
              <span class="text-lg font-bold text-indigo-400">{@room.word_limit} words</span>
            </div>
          </div>
          <%= if @room.intro_text do %>
            <p class="mt-3 text-slate-300 text-sm leading-relaxed border-t border-slate-700/40 pt-3">
              {@room.intro_text}
            </p>
          <% end %>
        </div>

        <!-- Submission Form or Submitted Confirmation -->
        <div class="bg-slate-800/80 backdrop-blur-md rounded-2xl p-6 border border-slate-700/60 shadow-xl">
          <%= if @submitted? do %>
            <div class="text-center py-4 space-y-2">
              <div class="mx-auto w-12 h-12 bg-emerald-500/10 rounded-full flex items-center justify-center text-emerald-400 mb-2 border border-emerald-500/20">
                <.icon name="hero-check-circle" class="w-7 h-7" />
              </div>
              <h3 class="text-lg font-bold text-white">Your Question Has Been Submitted</h3>
              <p class="text-sm text-slate-400 max-w-md mx-auto">
                "{@user_question.content}"
              </p>
              <p class="text-xs text-slate-500 pt-2">
                You can ask 1 question per event. You can still upvote questions asked by others below!
              </p>
            </div>
          <% else %>
            <h3 class="text-lg font-semibold text-white mb-3">Ask a Question Anonymously</h3>
            <.form
              for={@form}
              id="question-form"
              phx-change="validate_question"
              phx-submit="submit_question"
              class="space-y-4"
            >
              <div>
                <.input
                  id="question-content-input"
                  name={@form[:content].name}
                  value={@form[:content].value}
                  type="textarea"
                  placeholder="What would you like to ask?"
                  class="w-full bg-slate-900/90 border-slate-700 text-white rounded-xl p-3.5 focus:border-indigo-500 focus:ring-indigo-500 resize-none h-28"
                />
              </div>
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <span class={[
                    "px-2.5 py-1 rounded-lg text-xs font-bold border transition-all",
                    if(@word_count > @room.word_limit,
                      do: "bg-rose-500/20 text-rose-300 border-rose-500/40",
                      else: "bg-slate-900 text-slate-300 border-slate-700"
                    )
                  ]}>
                    {@word_count} / {@room.word_limit} words
                  </span>
                  <span class="text-xs text-slate-400">Anonymous submission</span>
                </div>
                <button
                  type="submit"
                  disabled={@word_count > @room.word_limit}
                  class="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-semibold text-white bg-gradient-to-r from-indigo-500 to-purple-600 hover:from-indigo-600 hover:to-purple-700 shadow-lg shadow-indigo-500/20 transition-all duration-200 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <.icon name="hero-paper-airplane" class="w-4 h-4" /> Submit
                </button>
              </div>
            </.form>
          <% end %>
        </div>

        <!-- Live Audience Questions Feed -->
        <div class="space-y-4">
          <div class="flex items-center justify-between px-1">
            <h2 class="text-lg font-bold text-white flex items-center gap-2">
              <.icon name="hero-chat-bubble-left-right" class="w-5 h-5 text-indigo-400" />
              Audience Questions ({length(@questions)})
            </h2>
            <span class="text-xs text-slate-400">Sorted by votes</span>
          </div>

          <%= if Enum.empty?(@questions) do %>
            <div class="bg-slate-800/40 rounded-2xl p-8 text-center border border-slate-700/40">
              <.icon
                name="hero-chat-bubble-bottom-center-text"
                class="w-10 h-10 text-slate-500 mx-auto mb-2"
              />
              <p class="text-slate-400 font-medium">No questions asked yet.</p>
              <p class="text-xs text-slate-500 mt-1">Be the first to submit a question!</p>
            </div>
          <% else %>
            <div id="questions-feed" class="space-y-3">
              <%= for question <- @questions do %>
                <div
                  id={"q-#{question.id}"}
                  class="bg-slate-800/80 backdrop-blur-md rounded-2xl p-5 border border-slate-700/60 shadow-lg flex items-start gap-4 transition-all duration-200 hover:border-slate-600"
                >
                  <!-- Vote Button Column -->
                  <button
                    phx-click="toggle_vote"
                    phx-value-id={question.id}
                    class={[
                      "flex flex-col items-center justify-center p-2.5 rounded-xl min-w-[54px] border transition-all duration-200",
                      if(MapSet.member?(@user_voted_ids, question.id),
                        do:
                          "bg-indigo-600/20 border-indigo-500/50 text-indigo-400 shadow-md shadow-indigo-500/10",
                        else:
                          "bg-slate-900/60 border-slate-700/60 text-slate-400 hover:border-slate-500 hover:text-white"
                      )
                    ]}
                  >
                    <.icon name="hero-chevron-up" class="w-5 h-5" />
                    <span class="text-sm font-bold mt-0.5">{question.vote_count}</span>
                  </button>

                  <!-- Content Column -->
                  <div class="flex-1 min-w-0 pt-0.5">
                    <p class="text-slate-100 text-base leading-relaxed break-words">
                      {question.content}
                    </p>
                    <div class="mt-2 flex items-center gap-3 text-xs text-slate-400">
                      <span>Anonymous</span>
                      <span>•</span>
                      <span>{Calendar.strftime(question.inserted_at, "%I:%M %p")}</span>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </QaAppWeb.Layouts.app>
    """
  end
end
