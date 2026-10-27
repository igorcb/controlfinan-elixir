defmodule ControlFinan.Repo do
  use Ecto.Repo, otp_app: :controlfinan, adapter: Ecto.Adapters.Postgres

  @doc "Creates the tables (same schema as the Rails app) when they do not exist."
  def migrate do
    Application.app_dir(:controlfinan, "priv/schema.sql")
    |> File.read!()
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(&query!/1)
  end

  @doc "Supervisor child that runs the schema once, before the endpoint starts."
  def migrate_child do
    migrate()
    :ignore
  end
end
