defmodule QaApp.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    room_expiry_scheduler =
      if Application.get_env(:qa_app, :room_expiry_scheduler_enabled, true) do
        QaApp.RoomExpiryScheduler
      end

    children =
      [
        QaAppWeb.Telemetry,
        QaApp.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:qa_app, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:qa_app, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: QaApp.PubSub},
        # Tracks live visitors per room; used by capacity limits and counts.
        QaApp.Presence,
        # Runs housekeeping on boot and keeps a timer for the soonest room expiry.
        room_expiry_scheduler,
        # Start to serve requests, typically the last entry
        QaAppWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: QaApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    QaAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
