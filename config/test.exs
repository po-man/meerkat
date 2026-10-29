import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :qa_app, QaApp.Repo,
  database: Path.expand("../qa_app_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox,
  pragmas: [
    journal_mode: :wal,
    synchronous: :normal,
    busy_timeout: 5000
  ]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :qa_app, QaAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "z5DPYAax+LvZ2/QFcQxDuiSDC8DZIsSYlEb5QUgyHYJ5HOImvjKTWy+hk8vfmIYB",
  server: false

# In test we don't send emails
config :qa_app, QaApp.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# The room expiry scheduler queries the database on boot (housekeeping), which
# conflicts with the SQL sandbox in manual mode. It is exercised separately in
# its own tests via `start_supervised!/1`.
config :qa_app, :room_expiry_scheduler_enabled, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
