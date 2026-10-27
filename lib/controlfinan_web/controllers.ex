defmodule ControlFinanWeb.MiscController do
  use Phoenix.Controller, formats: []
  import Plug.Conn
  alias ControlFinanWeb.Web

  def up(conn, _params) do
    conn
    |> put_resp_content_type("text/html", "utf-8")
    |> send_resp(200, ~s(<!DOCTYPE html><html><body style="background-color: green"></body></html>))
  end

  def search_account(conn, _params) do
    Web.redirect(conn, "/current_accounts?date=" <> Web.query_value(conn, "date_calendar_now"), 301)
  end

  def not_found(conn, _params), do: Web.not_found(conn)
end

defmodule ControlFinanWeb.SessionController do
  use Phoenix.Controller, formats: []
  import ControlFinanWeb.Web
  alias ControlFinan.Accounts

  plug :limit when action == :create
  plug :require_authentication when action == :delete

  defp limit(conn, _), do: rate_limit(conn, "sessions", "/session/new")

  def new(conn, _params) do
    render_page(conn, "sessions_new", 200, %{email_address: query_value(conn, "email_address")})
  end

  def create(conn, _params) do
    user = Accounts.find_by_email(form_value(conn, "email_address"))
    # Burn the same time as a real check to avoid user enumeration by timing.
    if user == nil, do: Accounts.burn_time()

    if user && Accounts.check_password?(user, form_value(conn, "password")) do
      conn = start_new_session_for(conn, user)
      {conn, url} = after_authentication_url(conn)
      redirect(conn, url, 302)
    else
      redirect_with(conn, "/session/new", 302, %{"alert" => "E-mail ou senha inválidos."})
    end
  end

  def delete(conn, _params), do: conn |> terminate_session() |> redirect("/session/new", 303)
end

defmodule ControlFinanWeb.RegistrationController do
  use Phoenix.Controller, formats: []
  import ControlFinanWeb.Web
  alias ControlFinan.Accounts

  plug :limit when action == :create

  defp limit(conn, _), do: rate_limit(conn, "registrations", "/registration/new")

  def new(conn, _params), do: render_page(conn, "registrations_new", 200, %{email_address: "", errors: []})

  def create(conn, _params) do
    password = form_value(conn, "user", "password")
    confirmation = form_value(conn, "user", "password_confirmation")
    {user, errors} = Accounts.validate(%Accounts.User{email_address: form_value(conn, "user", "email_address")}, password, confirmation)

    if errors != [] do
      render_page(conn, "registrations_new", 422, %{email_address: user.email_address, errors: errors})
    else
      user = Accounts.create(%{user | password_digest: Accounts.hash_password(password)})
      conn |> start_new_session_for(user) |> redirect_with("/", 302, %{"notice" => "Conta criada."})
    end
  end
end

defmodule ControlFinanWeb.PasswordController do
  @moduledoc "The reset token is signed, expires in 15 minutes and stops working once the password changes."
  use Phoenix.Controller, formats: []
  import ControlFinanWeb.Web
  alias ControlFinan.{Accounts, Clock, Mailer}

  @max_age 15 * 60
  @invalid "O link de redefinição é inválido ou expirou."

  plug :limit when action == :create

  defp limit(conn, _), do: rate_limit(conn, "passwords", "/passwords/new")

  defp b64(data), do: Base.url_encode64(data, padding: false)
  defp digest_tail(%Accounts.User{password_digest: d}), do: binary_part(d, byte_size(d) - 10, 10)

  def reset_token(%Accounts.User{} = user) do
    payload = "#{user.id}:#{digest_tail(user)}:#{Clock.unix() + @max_age}"
    b64(payload) <> "." <> b64(hmac("password_reset:" <> payload))
  end

  def find_by_reset_token(token) do
    with [encoded, signature] <- String.split(token, ".", parts: 2),
         {:ok, payload} <- Base.url_decode64(encoded, padding: false),
         true <- Plug.Crypto.secure_compare(b64(hmac("password_reset:" <> payload)), signature),
         [id, tail, expires] <- String.split(payload, ":"),
         {id, ""} <- Integer.parse(id),
         {expires, ""} <- Integer.parse(expires),
         true <- Clock.unix() <= expires,
         %Accounts.User{} = user <- Accounts.find(id),
         true <- digest_tail(user) == tail do
      user
    else
      _ -> nil
    end
  end

  def new(conn, _params), do: render_page(conn, "passwords_new", 200, %{email_address: query_value(conn, "email_address")})

  def create(conn, _params) do
    if user = Accounts.find_by_email(form_value(conn, "email_address")) do
      url = absolute_url(conn, "/passwords/" <> reset_token(user) <> "/edit")
      text = "Você pode redefinir sua senha em\n" <> url <> "\n\nEste link expira em 15 minutos.\n"
      Mailer.deliver(user.email_address, "Redefinição de senha", text)
    end

    redirect_with(conn, "/session/new", 302, %{
      "notice" => "Se o e-mail estiver cadastrado, enviamos as instruções para redefinir a senha."
    })
  end

  def edit(conn, %{"token" => token}) do
    if find_by_reset_token(token) do
      render_page(conn, "passwords_edit", 200, %{token: token})
    else
      redirect_with(conn, "/passwords/new", 302, %{"alert" => @invalid})
    end
  end

  def update(conn, %{"token" => token}) do
    case find_by_reset_token(token) do
      nil ->
        redirect_with(conn, "/passwords/new", 302, %{"alert" => @invalid})

      user ->
        password = form_value(conn, "password")
        {user, errors} = Accounts.validate(user, password, form_value(conn, "password_confirmation"))

        if errors != [] do
          redirect_with(conn, "/passwords/" <> token <> "/edit", 302, %{
            "alert" => "As senhas não conferem ou têm menos de 6 caracteres."
          })
        else
          user = Accounts.update_password(%{user | password_digest: Accounts.hash_password(password)})
          Accounts.delete_sessions_of(user)
          redirect_with(conn, "/session/new", 302, %{"notice" => "Senha redefinida."})
        end
    end
  end
end

defmodule ControlFinanWeb.EntryController do
  use Phoenix.Controller, formats: []
  import Plug.Conn
  import ControlFinanWeb.Web
  alias ControlFinan.{Clock, Entries, Format}
  alias ControlFinan.Entries.Entry

  @per_page 30

  plug :require_authentication

  defp user_id(conn), do: conn.assigns.current_user.id

  def parse_date(value) do
    with true <- Regex.match?(~r/\A\d{4}-\d{2}-\d{2}\z/, value),
         {:ok, date} <- Date.from_iso8601(value) do
      date
    else
      _ -> nil
    end
  end

  defp parse_page(value) do
    case Regex.match?(~r/\A[+-]?\d+\z/, value) && Integer.parse(String.trim_leading(value, "+")) do
      {page, ""} -> max(page, 1)
      _ -> 1
    end
  end

  # Compact JSON like jbuilder, with the same field order, no escaping of "/" or accents.
  defp entry_json(conn, %Entry{} = e) do
    historic = if e.historic == nil, do: "null", else: Jason.encode!(e.historic, escape: :javascript_safe)

    ~s({"id":#{e.id},"cash_account_id":#{e.cash_account_id},"cost_id":#{e.cost_id},) <>
      ~s("date_ocurrence":"#{Entries.date_iso(e)}","price":"#{Format.decimal_text(e.price_cents)}",) <>
      ~s("historic":#{historic},"user_id":#{e.user_id},"type_launche":#{e.type_launche},) <>
      ~s("url":#{Jason.encode!(absolute_url(conn, "/current_accounts/#{e.id}.json"), escape: :javascript_safe)}})
  end

  defp send_json(conn, body) do
    conn |> put_resp_content_type("application/json", "utf-8") |> send_resp(200, body)
  end

  def index(conn, _params) do
    day = parse_date(query_value(conn, "date"))
    page = parse_page(query_value(conn, "page"))
    entries = Entries.list(user_id(conn), day, @per_page + 1, (page - 1) * @per_page)
    next_page = length(entries) > @per_page
    entries = Enum.take(entries, @per_page)

    if String.ends_with?(conn.request_path, ".json") do
      send_json(conn, "[" <> Enum.map_join(entries, ",", &entry_json(conn, &1)) <> "]")
    else
      balance = Entries.balance(user_id(conn), day)

      {date_param, date_label, date_value} =
        if day,
          do: {"date=#{Date.to_iso8601(day)}&", Calendar.strftime(day, "%d/%m/%Y"), Date.to_iso8601(day)},
          else: {"", "", ""}

      render_page(conn, "current_accounts_index", 200, %{
        nav: "index", entries: entries, balance: balance, date_label: date_label, date_value: date_value,
        date_param: date_param, page: page, next_page: next_page
      })
    end
  end

  # Loads the signed in user's entry; other users' entries are "not found".
  defp with_entry(conn, raw, fun) do
    json? = String.ends_with?(raw, ".json")

    with {id, ""} <- Integer.parse(String.replace_suffix(raw, ".json", "")),
         %Entry{} = e <- Entries.find(user_id(conn), id) do
      fun.(e, json?)
    else
      _ -> not_found(conn)
    end
  end

  def show(conn, %{"id" => raw}) do
    with_entry(conn, raw, fn e, json? ->
      if json?, do: send_json(conn, entry_json(conn, e)), else: render_page(conn, "current_accounts_show", 200, %{entry: e})
    end)
  end

  defp form_assigns(e, errors), do: %{entry: e, errors: errors}

  def new(conn, _params) do
    e = %Entry{date: Clock.today(), type_launche: Entries.debit(), cash_account_id: -1, cost_id: -1}
    render_page(conn, "current_accounts_new", 200, form_assigns(e, []))
  end

  def edit(conn, %{"id" => raw}) do
    with_entry(conn, raw, fn e, _ -> render_page(conn, "current_accounts_edit", 200, form_assigns(e, [])) end)
  end

  # Copies the form fields into the entry and returns it with the validation messages.
  defp assign_form(conn, %Entry{} = e) do
    field = fn name -> form_value(conn, "current_account", name) end

    integer = fn name ->
      value = String.trim(field.(name))
      if Regex.match?(~r/\A-?\d+\z/, value), do: String.to_integer(value), else: -1
    end

    type =
      case field.("type_launche") do
        "debito" -> Entries.debit()
        "credito" -> Entries.credit()
        _ -> 0
      end

    price_text = String.trim(field.("price"))
    price = parse_price(price_text)

    e = %{
      e
      | cash_account_id: integer.("cash_account_id"),
        cost_id: integer.("cost_id"),
        type_launche: type,
        date: parse_date(field.("date_ocurrence")),
        price_text: price_text,
        price_set: price != nil,
        price_cents: price || 0,
        historic: if(field.("historic") == "", do: nil, else: field.("historic"))
    }

    {e, Entries.validate(e)}
  end

  # A number like Ruby's Float(): "150", "12.5", "-3", "1e2". Rounded to cents.
  defp parse_price(text) do
    # Exponents are capped so a value like "1e999999" is "not a number" instead of a huge integer.
    if Regex.match?(~r/\A[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d{1,2})?\z/, text) do
      text = if String.starts_with?(text, "."), do: "0" <> text, else: text
      text = String.replace(text, ~r/\.(?=[eE]|\z)/, "")
      text |> Decimal.new() |> Decimal.mult(100) |> Decimal.round(0, :half_up) |> Decimal.to_integer()
    end
  end

  def create(conn, _params) do
    case assign_form(conn, %Entry{user_id: user_id(conn)}) do
      {e, []} ->
        Entries.save(e)
        redirect_with(conn, "/current_accounts", 302, %{"notice" => "Lançamento cadastrado."})

      {e, errors} ->
        render_page(conn, "current_accounts_new", 422, form_assigns(e, errors))
    end
  end

  def update(conn, %{"id" => raw}) do
    with_entry(conn, raw, fn e, _ ->
      case assign_form(conn, e) do
        {e, []} ->
          Entries.save(e)
          redirect_with(conn, "/current_accounts/#{e.id}", 302, %{"notice" => "Lançamento atualizado."})

        {e, errors} ->
          render_page(conn, "current_accounts_edit", 422, form_assigns(e, errors))
      end
    end)
  end

  def delete(conn, %{"id" => raw}) do
    with_entry(conn, raw, fn e, _ ->
      Entries.delete(e)
      redirect_with(conn, "/current_accounts", 303, %{"notice" => "Lançamento removido."})
    end)
  end
end

defmodule ControlFinanWeb.DashboardController do
  use Phoenix.Controller, formats: []
  import ControlFinanWeb.Web
  alias ControlFinan.{Clock, Entries}

  @months ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)

  plug :require_authentication

  def parse_month(value) do
    with [_, year, month] <- Regex.run(~r/\A(\d{4})-(\d{1,2})\z/, value),
         month when month in 1..12 <- String.to_integer(month) do
      Date.new!(String.to_integer(year), month, 1)
    else
      _ -> Date.beginning_of_month(Clock.today())
    end
  end

  defp year_month(date), do: date |> Date.to_iso8601() |> binary_part(0, 7)

  def show(conn, _params) do
    month = parse_month(query_value(conn, "month"))
    summary = Entries.summarize_month(conn.assigns.current_user.id, month)
    label = String.capitalize(Enum.at(@months, month.month - 1)) <> " de " <> Integer.to_string(month.year)

    render_page(conn, "dashboards_show", 200, %{
      nav: "dashboard",
      month_label: label,
      today: Date.to_iso8601(Clock.today()),
      previous_month: month |> Date.shift(month: -1) |> year_month(),
      next_month: month |> Date.shift(month: 1) |> year_month(),
      summary: summary
    })
  end
end
