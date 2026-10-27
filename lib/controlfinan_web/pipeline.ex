defmodule ControlFinanWeb.Pipeline do
  @moduledoc "The Rails-like request pipeline, before the router: method override, CSRF check and session."
  @behaviour Plug
  import Plug.Conn
  alias ControlFinanWeb.Web

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{method: "POST"} = conn, _opts) do
    conn = fetch_cookies(conn)

    conn =
      case String.upcase(Web.form_value(conn, "_method")) do
        method when method in ["PUT", "PATCH", "DELETE"] -> %{conn | method: method}
        _ -> conn
      end

    if Web.valid_csrf?(conn) do
      Web.resume_session(conn)
    else
      conn |> Web.text_error(422, "Unprocessable Content") |> halt()
    end
  end

  def call(conn, _opts), do: conn |> fetch_cookies() |> Web.resume_session()
end
