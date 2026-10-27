defmodule QaAppWeb.SessionHTML do
  use QaAppWeb, :html

  def new(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto px-6 pt-20 sm:pt-28 pb-24">
        <div class="grid grid-cols-12">
          <div class="col-span-12 md:col-span-5 md:col-start-4 lg:col-span-4 lg:col-start-5">
            <p class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 flex items-center gap-2.5">
              <span class="w-2 h-2 bg-accent"></span>
              {if @setup_mode, do: "First-time setup", else: "Restricted area"}
            </p>

            <h2 class="mt-6 text-3xl sm:text-4xl font-semibold tracking-[-0.03em] text-ink">
              {if @setup_mode, do: "Admin Setup", else: "Admin Portal"}
            </h2>

            <p class="mt-3 text-sm leading-relaxed text-ink-2">
              {if @setup_mode,
                do: "First-time setup. Enter the access code to initialize the admin account.",
                else: "Sign in to manage your Q&A events"}
            </p>

            <%= if @error_message do %>
              <div class="mt-8 border border-danger/30 border-l-2 border-l-danger rounded px-3.5 py-2.5 text-[13px] text-danger">
                {@error_message}
              </div>
            <% end %>

            <.form :let={f} for={%{}} action={@login_path} class="mt-10 space-y-5">
              <%= if @setup_mode do %>
                <div>
                  <.input
                    field={f[:access_code]}
                    type="password"
                    required
                    label="Access Code"
                    placeholder="ADMIN_ACCESS_CODE"
                  />
                </div>
              <% end %>

              <div>
                <.input
                  field={f[:username]}
                  type="text"
                  required
                  label="Username"
                  placeholder={if @setup_mode, do: "admin", else: "moderator"}
                />
              </div>

              <div>
                <.input
                  field={f[:password]}
                  type="password"
                  required
                  label="Password"
                  placeholder="••••••••"
                />
              </div>

              <div class="pt-2">
                <button
                  type="submit"
                  class="w-full inline-flex items-center justify-center h-11 px-4 rounded bg-ink text-paper text-sm font-medium hover:bg-accent transition-colors duration-150"
                >
                  {if @setup_mode, do: "Initialize System", else: "Sign In"}
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </QaAppWeb.Layouts.app>
    """
  end
end
