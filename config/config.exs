import Config

config :controlfinan, ecto_repos: [ControlFinan.Repo]
config :controlfinan, ControlFinanWeb.Endpoint, adapter: Bandit.PhoenixAdapter, server: true
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
config :phoenix, :json_library, Jason
config :logger, level: :info

import_config "#{config_env()}.exs"
