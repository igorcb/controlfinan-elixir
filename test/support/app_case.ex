defmodule ControlFinan.AppCase do
  @moduledoc """
  Tests run against a real Postgres database, emptied before each test. Requests go through the whole
  endpoint (static, parsers, method override, CSRF, session, router) with a cookie jar, like a browser.
  """
  use ExUnit.CaseTemplate
  alias ControlFinan.{Accounts, Entries, Repo}

  using do
    quote do
      import ControlFinan.AppCase
      alias ControlFinan.{Accounts, Clock, Entries, FakeMailer, Format, Repo}
    end
  end

  setup do
    Repo.query!("TRUNCATE sessions, current_accounts, users RESTART IDENTITY CASCADE")
    ControlFinan.RateLimiter.reset()
    ControlFinan.FakeMailer.reset()
    ControlFinan.Clock.freeze(DateTime.new!(~D[2026-10-27], ~T[12:00:00], "America/Sao_Paulo"))
    on_exit(&ControlFinan.Clock.unfreeze/0)
    {:ok, jar: new_jar()}
  end

  def new_jar, do: start_supervised!({Agent, fn -> %{} end}, id: make_ref())

  @host "www.example.com"
  def base_url, do: "http://" <> @host

  def get(jar, path), do: request(jar, "GET", path, nil)

  @doc "Sends a form like the browser does, with the CSRF token from the cookie."
  def post(jar, path, form \\ []) do
    form =
      if List.keymember?(form, "authenticity_token", 0) do
        form
      else
        if csrf_token(jar) == nil, do: get(jar, "/passwords/new")
        form ++ [{"authenticity_token", csrf_token(jar)}]
      end

    request(jar, "POST", path, URI.encode_query(form))
  end

  def csrf_token(jar), do: Agent.get(jar, &Map.get(&1, "_csrf_token"))

  def request(jar, method, path, body) do
    cookies = Agent.get(jar, & &1)

    conn =
      Plug.Test.conn(method, path, body)
      |> Map.put(:host, @host)
      |> then(fn conn -> Enum.reduce(cookies, conn, fn {k, v}, c -> Plug.Test.put_req_cookie(c, k, v) end) end)
      |> then(fn conn ->
        if body, do: Plug.Conn.put_req_header(conn, "content-type", "application/x-www-form-urlencoded"), else: conn
      end)
      |> ControlFinanWeb.Endpoint.call([])

    Agent.update(jar, fn jar ->
      Enum.reduce(conn.resp_cookies, jar, fn {name, cookie}, jar ->
        if cookie[:max_age] == 0 or cookie[:value] in [nil, ""],
          do: Map.delete(jar, name),
          else: Map.put(jar, name, cookie.value)
      end)
    end)

    location =
      case Plug.Conn.get_resp_header(conn, "location") do
        [location] -> String.replace_prefix(location, base_url(), "")
        [] -> nil
      end

    %{status: conn.status, body: conn.resp_body, location: location}
  end

  def create_user(email, password) do
    Accounts.create(%Accounts.User{email_address: email, password_digest: Accounts.hash_password(password, 4)})
  end

  @doc "Creates a user and signs in through the real login form."
  def sign_in(jar) do
    user = create_user("driver@example.com", "secret123")
    res = post(jar, "/session", [{"email_address", "driver@example.com"}, {"password", "secret123"}])
    if res.status != 302, do: raise("sign in failed: #{res.status}")
    user
  end

  def create_entry(user, attrs \\ []) do
    kind = Keyword.get(attrs, :kind, Entries.credit())
    cost = Keyword.get(attrs, :cost, if(kind == Entries.credit(), do: Entries.rides(), else: 0))

    Entries.save(%Entries.Entry{
      user_id: user.id,
      cash_account_id: 5,
      cost_id: cost,
      type_launche: kind,
      date: Date.from_iso8601!(Keyword.get(attrs, :date, "2026-10-27")),
      price_cents: Keyword.get(attrs, :cents, 15000),
      price_set: true,
      historic: Keyword.get(attrs, :historic)
    })
  end

  def count(sql, args \\ []) do
    %{rows: [[n]]} = Repo.query!(sql, args)
    n
  end

  defmacro assert_contains(body, texts) do
    quote do
      body = unquote(body)
      for text <- List.wrap(unquote(texts)), do: assert(body =~ text, "expected body to contain #{inspect(text)}")
    end
  end

  defmacro refute_contains(body, texts) do
    quote do
      body = unquote(body)
      for text <- List.wrap(unquote(texts)), do: refute(body =~ text, "expected body not to contain #{inspect(text)}")
    end
  end

  def assert_in_order(body, texts) do
    pattern = Enum.map_join(texts, fn t -> "(?s).*" <> Regex.escape(t) end)
    assert Regex.match?(Regex.compile!(pattern, "u"), body), "expected body to contain in order: #{inspect(texts)}"
  end
end
