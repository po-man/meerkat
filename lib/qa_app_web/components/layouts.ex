defmodule QaAppWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use QaAppWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_user, :map,
    default: nil,
    doc:
      "the signed-in user (QaApp.Accounts.User). Pass it on auth-protected pages to show the user chip and Sign Out button"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="sticky top-0 z-40 bg-paper border-b border-line">
      <div class="max-w-6xl mx-auto px-6 h-14 flex items-center justify-between">
        <.link href={~p"/"} class="flex items-center gap-2.5 group">
          <span class="w-2.5 h-2.5 bg-accent transition-transform duration-150 group-hover:scale-90"></span>
          <span class="text-[15px] font-semibold tracking-[-0.02em] text-ink">Live Q&amp;A</span>
        </.link>

        <div class="flex items-center gap-4">
          <.theme_toggle />

          <%= if @current_user do %>
            <span class="hidden sm:flex items-center gap-2 font-mono text-xs text-ink-2">
              {@current_user.username}
              <span class="text-ink-3/60">/</span>
              <span class="uppercase tracking-[0.14em] text-ink-3">{@current_user.role}</span>
            </span>

            <.link
              id="sign-out"
              href={~p"/logout"}
              method="delete"
              class="text-[13px] font-medium text-ink-2 hover:text-ink transition-colors underline-offset-4 hover:underline"
            >
              Sign Out
            </.link>
          <% end %>
        </div>
      </div>
    </header>

    <main class="min-h-[calc(100vh-3.5rem)]">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages to display"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides light vs dark theme toggle based on the data-theme
  attribute applied before paint in layouts/root.html.heex.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div
      class="flex items-stretch h-8 border border-line-strong rounded overflow-hidden"
      aria-label="Theme"
    >
      <button
        type="button"
        class="theme-opt theme-opt-system w-8 flex items-center justify-center cursor-pointer"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="System theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        type="button"
        class="theme-opt theme-opt-light w-8 flex items-center justify-center cursor-pointer border-l border-line-strong"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Light theme"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        type="button"
        class="theme-opt theme-opt-dark w-8 flex items-center justify-center cursor-pointer border-l border-line-strong"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
