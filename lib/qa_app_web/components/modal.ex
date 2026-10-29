defmodule QaAppWeb.Components.Modal do
  @moduledoc """
  Reusable modal shell (backdrop, panel and close button) shared by the
  admin control center modals. Inner content is passed as a slot.
  """

  use Phoenix.Component
  import QaAppWeb.CoreComponents

  @doc """
  Renders a centered modal panel over a dimmed backdrop.

  ## Examples

      <.modal close_event="close_configure_room">
        <div class="space-y-5">…form…</div>
      </.modal>
  """
  attr :close_event, :string,
    required: true,
    doc: "the `phx-click` event that closes the modal"

  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40">
      <div class="bg-paper border border-line-strong rounded-lg p-6 sm:p-8 max-w-md w-full space-y-5 relative">
        <button
          phx-click={@close_event}
          aria-label="Close"
          class="absolute top-3 right-3 w-9 h-9 rounded border border-transparent hover:border-line-strong flex items-center justify-center text-ink-3 hover:text-ink transition-colors"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
