defmodule QaAppWeb.SetupHTML do
  use QaAppWeb, :html

  def new(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash}>
      <div class="min-h-[80vh] flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
        <div class="max-w-md w-full space-y-8 bg-slate-800/80 backdrop-blur-md p-8 rounded-2xl border border-amber-500/30 shadow-2xl">
          <div>
            <div class="mx-auto w-12 h-12 bg-amber-500/10 rounded-2xl flex items-center justify-center text-amber-400 mb-4 border border-amber-500/20">
              <.icon name="hero-shield-check" class="w-6 h-6" />
            </div>
            <h2 class="text-center text-3xl font-extrabold text-white">
              Super Admin Setup
            </h2>
            <p class="mt-2 text-center text-sm text-slate-400">
              Initialize system administrator account
            </p>
          </div>

          <%= if @error_message do %>
            <div class="bg-rose-500/10 border border-rose-500/30 text-rose-300 p-3 rounded-xl text-sm text-center">
              {@error_message}
            </div>
          <% end %>

          <.form :let={f} for={%{}} action={~p"/super-admin/setup"} class="mt-8 space-y-6">
            <div class="space-y-4">
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
              <div>
                <label class="block text-sm font-medium text-slate-300 mb-1">Admin Username</label>
                <.input
                  field={f[:username]}
                  type="text"
                  required
                  class="w-full bg-slate-900/80 border-slate-700 text-white rounded-xl px-4 py-2.5 focus:border-amber-500 focus:ring-amber-500"
                  placeholder="superadmin"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-slate-300 mb-1">Password</label>
                <.input
                  field={f[:password]}
                  type="password"
                  required
                  class="w-full bg-slate-900/80 border-slate-700 text-white rounded-xl px-4 py-2.5 focus:border-amber-500 focus:ring-amber-500"
                  placeholder="••••••••"
                />
              </div>
            </div>

            <div>
              <button
                type="submit"
                class="w-full flex justify-center py-3 px-4 border border-transparent text-sm font-medium rounded-xl text-white bg-gradient-to-r from-amber-500 to-orange-600 hover:from-amber-600 hover:to-orange-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-amber-500 shadow-lg shadow-amber-500/20 transition-all duration-200"
              >
                Initialize System
              </button>
            </div>
          </.form>
        </div>
      </div>
    </QaAppWeb.Layouts.app>
    """
  end
end
