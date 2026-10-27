defmodule ControlFinan.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ControlFinan.Repo,
      %{id: :migrate, start: {ControlFinan.Repo, :migrate_child, []}, restart: :temporary},
      ControlFinan.RateLimiter,
      ControlFinanWeb.Endpoint
    ]

    ControlFinan.Accounts.prepare_dummy()
    Supervisor.start_link(children, strategy: :one_for_one, name: ControlFinan.Supervisor)
  end
end
