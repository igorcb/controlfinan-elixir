defmodule ControlFinanWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :controlfinan

  plug Plug.Static, at: "/", from: :controlfinan, only: ~w(css js icon.png icon.svg), gzip: false
  plug Plug.Parsers, parsers: [:urlencoded], pass: ["*/*"]
  plug ControlFinanWeb.Pipeline
  plug ControlFinanWeb.Router
end
