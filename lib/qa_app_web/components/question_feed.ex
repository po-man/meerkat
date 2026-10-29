defmodule QaAppWeb.Components.QuestionFeed do
  @moduledoc """
  Presentational components for question feeds.

  `moderator_question/1` renders a single moderator dashboard row in either
  its raised ("Mark as Asked") or asked ("Move back") state, so both tabs
  share one implementation.
  """

  use Phoenix.Component
  import QaAppWeb.CoreComponents

  @doc """
  Renders one row of the moderator question feed.

  ## Examples

      <.moderator_question question={question} index={index} />
      <.moderator_question question={question} index={index} asked? />
  """
  attr :question, QaApp.Engagement.Question, required: true
  attr :index, :integer, required: true
  attr :asked?, :boolean, default: false
  attr :id, :string, required: true, doc: "the stream item's DOM id"

  def moderator_question(assigns) do
    ~H"""
    <div id={@id} class="grid grid-cols-12 gap-x-4 sm:gap-x-6 items-start py-5 border-b border-line">
      <div class={if(@asked?, do: "col-span-2 sm:col-span-1", else: "col-span-1 sm:col-span-1")}>
        <span class="font-mono text-xs text-ink-3 tabular-nums">{@index}</span>
      </div>

      <div class="col-span-10 sm:col-span-8 flex items-start gap-4">
        <span class={[
          "shrink-0 w-11 py-2 rounded border flex flex-col items-center justify-center gap-0.5 font-mono text-xs tabular-nums",
          if(@asked?, do: "border-line text-ink-3", else: "border-line-strong text-ink")
        ]}>
          <.icon name="hero-chevron-up" class="size-3.5" />
          {@question.vote_count}
        </span>

        <div class="flex-1 min-w-0 pt-1">
          <p class="text-[16px] leading-relaxed text-ink break-words">{@question.content}</p>
          <div class="mt-2 flex items-center gap-3 font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">
            <span class="normal-case tracking-normal tabular-nums">
              Submitted
              <.local_datetime
                id={"submitted-at-#{@question.id}"}
                datetime={@question.inserted_at}
                format={:time}
              />
            </span>

            <%= if @asked? do %>
              <span class="text-ink-2 flex items-center gap-1.5">
                <span class="w-1.5 h-1.5 rounded-full bg-accent"></span> Asked
              </span>
            <% end %>
          </div>
        </div>
      </div>

      <div class="col-span-12 sm:col-span-3 flex justify-end pt-3 sm:pt-1">
        <%= if @asked? do %>
          <button
            phx-click="mark_unasked"
            phx-value-id={@question.id}
            class="inline-flex items-center gap-1.5 h-8 px-3 rounded border border-line-strong bg-transparent text-ink-2 text-xs font-medium hover:border-ink hover:text-ink transition-colors duration-150"
          >
            <.icon name="hero-arrow-uturn-left" class="size-3.5" /> Move back
          </button>
        <% else %>
          <button
            phx-click="mark_asked"
            phx-value-id={@question.id}
            class="inline-flex items-center gap-1.5 h-8 px-3 rounded border border-line-strong bg-transparent text-ink-2 text-xs font-medium hover:border-ink hover:text-ink transition-colors duration-150"
          >
            <.icon name="hero-check" class="size-3.5" /> Mark as Asked
          </button>
        <% end %>
      </div>
    </div>
    """
  end
end
