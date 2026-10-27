import Config

if config_env() != :test do
  config :controlfinan, ControlFinan.Repo,
    url: System.get_env("DATABASE_URL", "ecto://app:app@localhost:5432/controlfinan_elixir"),
    pool_size: String.to_integer(System.get_env("DB_POOL", "10"))

  secret = System.get_env("SECRET_KEY_BASE") || raise "SECRET_KEY_BASE is required"

  config :controlfinan,
    secret: secret,
    bcrypt_cost: String.to_integer(System.get_env("BCRYPT_COST", "12")),
    time_zone: System.get_env("APP_TIMEZONE", "America/Sao_Paulo")

  config :controlfinan, ControlFinanWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "8000"))],
    # Phoenix wants its own 64+ byte secret; the app's cookies are signed with SECRET_KEY_BASE itself.
    secret_key_base: Base.encode64(:crypto.hash(:sha512, "phoenix-endpoint:" <> secret))
end
