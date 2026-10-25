defmodule QaAppWeb.SessionHTML do
  use QaAppWeb, :html

  def new(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash}>
      <div class="min-h-[80vh] flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
        <div class={[
          "max-w-md w-full space-y-8 bg-slate-800/80 backdrop-blur-md p-8 rounded-2xl border shadow-2xl",
          if(@setup_mode, do: "border-amber-500/30", else: "border-slate-700/60")
        ]}>
          <div>
            <%= if @setup_mode do %>
              <div class="mx-auto w-12 h-12 bg-amber-500/10 rounded-2xl flex items-center justify-center text-amber-400 mb-4 border border-amber-500/20">
                <.icon name="hero-shield-check" class="w-6 h-6" />
              </div>
              <h2 class="text-center text-3xl font-extrabold text-white">
                Super Admin Setup
              </h2>
              <p class="mt-2 text-center text-sm text-slate-400">
                First-time setup. Enter the access code to initialize the super admin account.
              </p>
            <% else %>
              <div class="mx-auto w-12 h-12 bg-indigo-500/10 rounded-2xl flex items-center justify-center text-indigo-400 mb-4 border border-indigo-500/20">
                <.icon name="hero-key" class="w-6 h-6" />
              </div>
              <h2 class="mt-2 text-center text-3xl font-extrabold text-white">
                Admin Portal
              </h2>
              <p class="mt-2 text-center text-sm text-slate-400">
                Sign in to manage your Q&A events
              </p>
            <% end %>
          </div>

          <%= if @error_message do %>
            <div class="bg-rose-500/10 border border-rose-500/30 text-rose-300 p-3 rounded-xl text-sm text-center">
              {@error_message}
            </div>
          <% end %>

          <.form :let={f} for={%{}} action={@login_path} class="mt-8 space-y-6">
            <div class="space-y-4">
              <%= if @setup_mode do %>
                <div>
                  <label class="block text-sm font-medium text-slate-300 mb-1">Access Code</label>
                  <.input
                    field={f[:access_code]}
                    type="password"
                    required
                    class="w-full bg-slate-900/80 border-slate-700 text-white rounded-xl px-4 py-2.5 focus:border-amber-500 focus:ring-amber-500"
                    placeholder="SUPER_ADMIN_ACCESS_CODE"
                  />
                </div>
              <% end %>
              <div>
                <label class="block text-sm font-medium text-slate-300 mb-1">Username</label>
                <.input
                  field={f[:username]}
                  type="text"
                  required
                  class="w-full bg-slate-900/80 border-slate-700 text-white rounded-xl px-4 py-2.5 focus:border-indigo-500 focus:ring-indigo-500"
                  placeholder={if @setup_mode, do: "superadmin", else: "admin"}
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-slate-300 mb-1">Password</label>
                <.input
                  field={f[:password]}
                  type="password"
                  required
                  class="w-full bg-slate-900/80 border-slate-700 text-white rounded-xl px-4 py-2.5 focus:border-indigo-500 focus:ring-indigo-500"
                  placeholder="••••••••"
                />
              </div>
            </div>

            <div>
              <button
                type="submit"
                class={[
                  "w-full flex justify-center py-3 px-4 border border-transparent text-sm font-medium rounded-xl text-white shadow-lg transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-offset-2",
                  if(@setup_mode,
                    do:
                      "bg-gradient-to-r from-amber-500 to-orange-600 hover:from-amber-600 hover:to-orange-700 focus:ring-amber-500 shadow-amber-500/20",
                    else:
                      "bg-gradient-to-r from-indigo-500 to-purple-600 hover:from-indigo-600 hover:to-purple-700 focus:ring-indigo-500 shadow-indigo-500/20"
                  )
                ]}
              >
                {if @setup_mode, do: "Initialize System", else: "Sign In"}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </QaAppWeb.Layouts.app>
    """
  end
end
