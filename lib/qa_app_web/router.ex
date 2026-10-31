defmodule QaAppWeb.Router do
  use QaAppWeb, :router

  import QaAppWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {QaAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug QaAppWeb.Plugs.SessionId
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Chrome (with DevTools open) probes this on every page load. Answering with
  # 204 avoids a NoRouteError and its dev stacktrace without exposing anything.
  get "/.well-known/appspecific/com.chrome.devtools.json", QaAppWeb.PageController, :devtools

  scope "/", QaAppWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Static "room is full" page. Deliberately not a LiveView: waiting visitors
    # must not hold a WebSocket, which is what the visitor limit protects.
    get "/r/:slug/full", RoomFullController, :show

    # Combined sign-in / first-time setup page.
    # The path is intentionally secret (not linked from any public page),
    # see QaAppWeb.AdminAuth.
    get QaAppWeb.AdminAuth.secret_path(), SessionController, :new
    post QaAppWeb.AdminAuth.secret_path(), SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # Audience LiveView Routes
  live_session :audience, on_mount: [QaAppWeb.SessionLiveAuth] do
    scope "/", QaAppWeb do
      pipe_through :browser

      live "/r/:slug", AudienceLive.Show, :show
    end
  end

  # Admin LiveView Routes
  live_session :admin, on_mount: [{QaAppWeb.UserAuth, :require_admin}] do
    scope "/admin", QaAppWeb do
      pipe_through :browser

      live "/", AdminLive.Index, :index
    end
  end

  # Moderator LiveView Routes
  live_session :moderator, on_mount: [{QaAppWeb.UserAuth, :require_authenticated_user}] do
    scope "/moderator", QaAppWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/dashboard", ModeratorLive.Dashboard, :index
      live "/r/:slug/settings", ModeratorLive.Settings, :settings
      live "/r/:slug", ModeratorLive.Show, :show
      get "/r/:slug/export.csv", ExportController, :csv
      get "/r/:slug/qr.png", ExportController, :qr
    end
  end

  if Application.compile_env(:qa_app, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: QaAppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
