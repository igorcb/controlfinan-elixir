defmodule ControlFinanWeb.Web do
  @moduledoc """
  The Rails-like request helpers: signed cookies ("value--signature", HMAC-SHA256 with SECRET_KEY_BASE),
  session, CSRF double submit token, flash that survives one redirect, and rate limiting.
  """
  import Plug.Conn
  alias ControlFinan.Accounts

  @session_cookie "session_id"
  @csrf_cookie "_csrf_token"
  @flash_cookie "_flash"
  @return_to_cookie "return_to"
  # cookies.permanent
  @permanent_age 20 * 365 * 24 * 60 * 60

  def csrf_cookie, do: @csrf_cookie

  defp secret, do: Application.fetch_env!(:controlfinan, :secret)

  defp b64(data), do: Base.url_encode64(data, padding: false)

  def hmac(data), do: :crypto.mac(:hmac, :sha256, secret(), data)

  def sign(purpose, value), do: b64(value) <> "--" <> b64(hmac(purpose <> ":" <> value))

  def verify(purpose, signed) do
    with [encoded, _signature] <- String.split(signed, "--", parts: 2),
         {:ok, raw} <- Base.url_decode64(encoded, padding: false),
         true <- Plug.Crypto.secure_compare(sign(purpose, raw), signed) do
      {:ok, raw}
    else
      _ -> :error
    end
  end

  def set_cookie(conn, name, value, max_age \\ 0) do
    opts = [path: "/", http_only: true, same_site: "Lax"]
    opts = if max_age > 0, do: Keyword.put(opts, :max_age, max_age), else: opts
    put_resp_cookie(conn, name, value, opts)
  end

  def delete_cookie(conn, name), do: delete_resp_cookie(conn, name, path: "/", http_only: true, same_site: "Lax")

  def read_signed(conn, name) do
    case conn.req_cookies do
      %{^name => value} -> verify(name, value)
      _ -> :error
    end
  end

  # Authentication like Rails 8's generator: a signed "session_id" cookie pointing to a row in `sessions`.

  def resume_session(conn) do
    with {:ok, value} <- read_signed(conn, @session_cookie),
         {id, ""} <- Integer.parse(value),
         %Accounts.User{} = user <- Accounts.session_user(id) do
      conn |> assign(:current_user, user) |> assign(:session_id, id)
    else
      _ -> conn |> assign(:current_user, nil) |> assign(:session_id, nil)
    end
  end

  def start_new_session_for(conn, user) do
    user_agent = conn |> get_req_header("user-agent") |> List.first() || ""
    id = Accounts.create_session(user, user_agent, remote_ip(conn))
    set_cookie(conn, @session_cookie, sign(@session_cookie, Integer.to_string(id)), @permanent_age)
  end

  def terminate_session(conn) do
    if conn.assigns[:session_id], do: Accounts.delete_session(conn.assigns.session_id)
    delete_cookie(conn, @session_cookie)
  end

  @doc "Redirects guests to the login and remembers the page they asked for."
  def require_authentication(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> set_cookie(@return_to_cookie, sign(@return_to_cookie, absolute_url(conn, request_uri(conn))))
      |> redirect("/session/new", 302)
      |> halt()
    end
  end

  def after_authentication_url(conn) do
    case read_signed(conn, @return_to_cookie) do
      {:ok, url} -> {delete_cookie(conn, @return_to_cookie), url}
      :error -> {conn, absolute_url(conn, "/")}
    end
  end

  defp request_uri(%{query_string: ""} = conn), do: conn.request_path
  defp request_uri(conn), do: conn.request_path <> "?" <> conn.query_string

  def host(conn) do
    case get_req_header(conn, "host") do
      [host | _] -> host
      [] when conn.port in [80, 443] -> conn.host
      [] -> conn.host <> ":" <> Integer.to_string(conn.port)
    end
  end

  def absolute_url(conn, path), do: "http://" <> host(conn) <> path

  def remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  # CSRF protection with a random token kept in a cookie and repeated in every form (double submit).

  def csrf_token(conn) do
    case conn.req_cookies do
      %{@csrf_cookie => token} when token != "" ->
        {conn, token}

      _ ->
        token = b64(:crypto.strong_rand_bytes(32))
        {set_cookie(conn, @csrf_cookie, token), token}
    end
  end

  def valid_csrf?(conn) do
    case {conn.req_cookies, conn.body_params} do
      {%{@csrf_cookie => cookie}, %{"authenticity_token" => token}} when cookie != "" and is_binary(token) ->
        Plug.Crypto.secure_compare(cookie, token)

      _ ->
        false
    end
  end

  # Flash messages survive one redirect, like Rails' flash.

  def put_flash(conn, flash) do
    set_cookie(conn, @flash_cookie, sign(@flash_cookie, Jason.encode!(flash)))
  end

  def take_flash(conn) do
    with {:ok, value} <- read_signed(conn, @flash_cookie),
         {:ok, %{} = flash} <- Jason.decode(value) do
      {delete_cookie(conn, @flash_cookie), flash}
    else
      _ -> {conn, %{}}
    end
  end

  # Responses

  def render_page(conn, page, status, assigns) do
    {conn, flash} = take_flash(conn)
    {conn, token} = csrf_token(conn)

    assigns =
      Map.merge(%{nav: nil}, assigns)
      |> Map.merge(%{
        user: conn.assigns[:current_user],
        notice: Map.get(flash, "notice", ""),
        alert: Map.get(flash, "alert", ""),
        csrf: token
      })

    conn
    |> put_resp_content_type("text/html", "utf-8")
    |> send_resp(status, ControlFinanWeb.Templates.render(page, assigns))
  end

  @doc "Like Go's http.Redirect: a short HTML body only for GET and HEAD."
  def redirect(conn, url, status) do
    conn = put_resp_header(conn, "location", url)

    if conn.method in ["GET", "HEAD"] do
      text = Plug.Conn.Status.reason_phrase(status)
      href = url |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      conn
      |> put_resp_content_type("text/html", "utf-8")
      |> send_resp(status, ~s(<a href="#{href}">#{text}</a>.\n\n))
    else
      send_resp(conn, status, "")
    end
  end

  def redirect_with(conn, url, status, flash), do: conn |> put_flash(flash) |> redirect(url, status)

  def text_error(conn, status, text) do
    conn
    |> put_resp_content_type("text/plain", "utf-8")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(status, text <> "\n")
  end

  def not_found(conn), do: text_error(conn, 404, "404 page not found")

  @doc "Like Rails `rate_limit to: 10, within: 3.minutes`, per action and IP."
  def rate_limit(conn, name, back_to) do
    if ControlFinan.RateLimiter.allow?(name <> ":" <> remote_ip(conn), 10, 180) do
      conn
    else
      conn |> redirect_with(back_to, 302, %{"alert" => "Tente novamente mais tarde."}) |> halt()
    end
  end

  @doc "A form field as a string (\"\" when missing), like Go's PostFormValue."
  def form_value(conn, name), do: string(conn.body_params[name])
  def form_value(conn, scope, name), do: string(get_in_map(conn.body_params, scope, name))

  def query_value(conn, name), do: string(conn.query_params[name])

  defp get_in_map(params, scope, name) do
    case params[scope] do
      %{} = nested -> nested[name]
      _ -> nil
    end
  end

  defp string(value) when is_binary(value), do: value
  defp string(_), do: ""
end
