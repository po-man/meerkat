import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# This is skipped for :test so the test suite stays hermetic
# (fresh checkouts / CI have no `.env`; tests set the variable explicitly).
# Only :dev reads `.env`: in production, configuration must come from the
# environment so a stray file can never silently supply (or override) secrets.
env_file = Path.expand("../.env", __DIR__)

if config_env() == :dev and File.exists?(env_file) do
  env_file
  |> File.read!()
  |> String.split("\n")
  |> Enum.each(fn raw_line ->
    line = String.trim(raw_line)

    if line != "" and not String.starts_with?(line, "#") do
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          key = String.trim(key)
          value = value |> String.trim() |> String.trim("\"") |> String.trim("'")

          if key != "" and System.get_env(key) == nil do
            System.put_env(key, value)
          end

        _ ->
          :ok
      end
    end
  end)
end

if config_env() != :test and System.get_env("ADMIN_ACCESS_CODE") in [nil, ""] do
  raise """
  environment variable ADMIN_ACCESS_CODE is missing.
  Set it in `.env` for development (see `.env.sample`) or in the process
  environment for production (see docs/DEPLOY.md).
  """
end

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/qa_app start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :qa_app, QaAppWeb.Endpoint, server: true
end

config :qa_app, QaAppWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :qa_app, QaAppWeb.Endpoint,
    live_reload: [
      # Streaming server logs to the browser forwards every log line to every
      # connected tab, which can dominate a multi-client load test. Opt in with
      # `LIVE_RELOAD_LOGS=1 mix phx.server`.
      web_console_logger: System.get_env("LIVE_RELOAD_LOGS") == "1",
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/qa_app_web/router\.ex$"E,
        ~r"lib/qa_app_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/qa_app/qa_app.db
      """

  config :qa_app, QaApp.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    pragmas: [
      journal_mode: :wal,
      synchronous: :normal,
      busy_timeout: 5000
    ]

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # The public host is used to build links and the moderator QR codes, so a
  # wrong value is a visible production bug rather than a cosmetic default.
  host =
    case System.get_env("PHX_HOST") do
      nil ->
        raise """
        environment variable PHX_HOST is missing.
        Set it to the public hostname, for example: ask.example.com
        """

      "" ->
        raise """
        environment variable PHX_HOST is empty.
        Set it to the public hostname, for example: ask.example.com
        """

      host ->
        if String.contains?(host, "://") do
          raise """
          environment variable PHX_HOST must be a bare hostname, got: #{inspect(host)}.
          Use ask.example.com instead of https://ask.example.com
          """
        end

        host
    end

  config :qa_app, QaAppWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :qa_app, QaAppWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :qa_app, QaAppWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :qa_app, QaApp.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
