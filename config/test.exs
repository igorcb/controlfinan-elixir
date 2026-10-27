import Config

config :controlfinan, ControlFinan.Repo,
  url: System.get_env("TEST_DATABASE_URL", "ecto://app:app@localhost:5432/controlfinan_elixir_test"),
  pool_size: 10

config :controlfinan, ControlFinanWeb.Endpoint, server: false
config :controlfinan, secret: "test-secret", bcrypt_cost: 4, mailer: ControlFinan.FakeMailer
config :logger, level: :warning
