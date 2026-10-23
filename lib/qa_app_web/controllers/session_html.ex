defmodule QaAppWeb.SessionHTML do
  use QaAppWeb, :html

  def new(assigns) do
    ~H"""
    <QaAppWeb.Layouts.app flash={@flash}>
      <div class="min-h-[80vh] flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
        <div class="max-w-md w-full space-y-8 bg-slate-800/80 backdrop-blur-md p-8 rounded-2xl border border-slate-700/60 shadow-2xl">
          <div>
            <h2 class="mt-2 text-center text-3xl font-extrabold text-white">
              Admin Portal
            </h2>
            <p class="mt-2 text-center text-sm text-slate-400">
              Sign in to manage your Q&A events
            </p>
          </div>

          <%= if @error_message do %>
            <div class="bg-rose-500/10 border border-rose-500/30 text-rose-300 p-3 rounded-xl text-sm text-center">
              {@error_message}
            </div>
          <% end %>

          <.form :let={f} for={%{}} action={~p"/login"} class="mt-8 space-y-6">
            <div class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-slate-300 mb-1">Username</label>
                <.input
                  field={f[:username]}
                  type="text"
                  required
                  class="w-full bg-slate-900/80 border-slate-700 text-white rounded-xl px-4 py-2.5 focus:border-indigo-500 focus:ring-indigo-500"
                  placeholder="admin"
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
                class="w-full flex justify-center py-3 px-4 border border-transparent text-sm font-medium rounded-xl text-white bg-gradient-to-r from-indigo-500 to-purple-600 hover:from-indigo-600 hover:to-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 shadow-lg shadow-indigo-500/20 transition-all duration-200"
              >
                Sign In
              </button>
            </div>
          </.form>
        </div>
      </div>
    </QaAppWeb.Layouts.app>
    """
  end
end
