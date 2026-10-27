defmodule ControlFinanWeb.HandlersTest do
  use ControlFinan.AppCase
  alias ControlFinanWeb.PasswordController

  test "login form is shown", %{jar: jar} do
    res = get(jar, "/session/new")
    assert res.status == 200
    assert_contains(res.body, "Esqueceu a senha?")
  end

  test "guest is redirected to login and back after signing in", %{jar: jar} do
    create_user("driver@example.com", "secret123")

    assert get(jar, "/dashboard").location == "/session/new"
    res = post(jar, "/session", [{"email_address", " Driver@Example.com "}, {"password", "secret123"}])

    assert res.location == "/dashboard"
    assert count("SELECT count(*) FROM sessions") == 1
    assert get(jar, "/dashboard").status == 200
  end

  test "wrong password is rejected", %{jar: jar} do
    create_user("driver@example.com", "secret123")

    res = post(jar, "/session", [{"email_address", "driver@example.com"}, {"password", "wrong"}])

    assert res.location == "/session/new"
    assert_contains(get(jar, "/session/new").body, "E-mail ou senha inválidos.")
  end

  test "login attempts are limited to ten every three minutes", %{jar: jar} do
    form = [{"email_address", "x@example.com"}, {"password", "x"}]
    for _ <- 1..10, do: post(jar, "/session", form)
    post(jar, "/session", form)
    assert_contains(get(jar, "/session/new").body, "Tente novamente mais tarde.")

    Clock.freeze(DateTime.add(Clock.now(), 4 * 60))
    post(jar, "/session", form)
    assert_contains(get(jar, "/session/new").body, "E-mail ou senha inválidos.")
  end

  test "sign out deletes the session", %{jar: jar} do
    sign_in(jar)

    res = post(jar, "/session", [{"_method", "delete"}])

    assert res.status == 303
    assert res.location == "/session/new"
    assert count("SELECT count(*) FROM sessions") == 0
    assert get(jar, "/").location == "/session/new"
  end

  test "forms without a valid CSRF token are rejected", %{jar: jar} do
    create_user("driver@example.com", "secret123")
    get(jar, "/session/new")

    res = post(jar, "/session", [{"authenticity_token", "forged"}, {"email_address", "driver@example.com"}, {"password", "secret123"}])

    assert res.status == 422
    assert count("SELECT count(*) FROM sessions") == 0
  end

  test "registration creates an account and signs in", %{jar: jar} do
    res =
      post(jar, "/registration", [
        {"user[email_address]", " New@Example.com "},
        {"user[password]", "secret123"},
        {"user[password_confirmation]", "secret123"}
      ])

    assert res.location == "/"
    assert count("SELECT count(*) FROM users WHERE email_address = 'new@example.com'") == 1
    assert_contains(get(jar, "/").body, "Conta criada.")
  end

  test "registration shows the validation messages", %{jar: jar} do
    res =
      post(jar, "/registration", [{"user[email_address]", "bad"}, {"user[password]", "1"}, {"user[password_confirmation]", "2"}])

    assert res.status == 422
    assert_contains(res.body, ["Confirmação da senha não é igual a Senha", "E-mail não é válido"])
  end

  test "password reset email does not reveal whether the address exists", %{jar: jar} do
    create_user("driver@example.com", "secret123")
    notice = "Se o e-mail estiver cadastrado, enviamos as instruções para redefinir a senha."

    assert post(jar, "/passwords", [{"email_address", "driver@example.com"}]).location == "/session/new"
    assert_contains(get(jar, "/session/new").body, notice)
    post(jar, "/passwords", [{"email_address", "missing@example.com"}])
    assert_contains(get(jar, "/session/new").body, notice)

    assert [mail] = FakeMailer.sent()
    assert_contains(mail, ["driver@example.com|Redefinição de senha|", "/passwords/", "/edit", "15 minutos"])
  end

  test "password reset changes the password and ends every session", %{jar: jar} do
    user = sign_in(jar)
    token = PasswordController.reset_token(user)

    assert_contains(get(jar, "/passwords/#{token}/edit").body, "Defina sua nova senha")

    res =
      post(jar, "/passwords/#{token}", [{"_method", "put"}, {"password", "new-secret"}, {"password_confirmation", "new-secret"}])

    assert res.location == "/session/new"
    assert_contains(get(jar, "/session/new").body, "Senha redefinida.")
    assert count("SELECT count(*) FROM sessions") == 0
    assert Accounts.check_password?(Accounts.find(user.id), "new-secret")
  end

  test "password reset rejects passwords that do not match", %{jar: jar} do
    token = PasswordController.reset_token(create_user("driver@example.com", "secret123"))

    res = post(jar, "/passwords/#{token}", [{"_method", "put"}, {"password", "new-secret"}, {"password_confirmation", "other"}])

    assert res.location == "/passwords/#{token}/edit"
    assert_contains(get(jar, "/passwords/#{token}/edit").body, "As senhas não conferem ou têm menos de 6 caracteres.")
  end

  test "password reset token expires after fifteen minutes and after a password change", %{jar: jar} do
    user = create_user("driver@example.com", "secret123")
    token = PasswordController.reset_token(user)
    start = Clock.now()

    Clock.freeze(DateTime.add(start, 16 * 60))
    assert get(jar, "/passwords/#{token}/edit").location == "/passwords/new"
    assert_contains(get(jar, "/passwords/new").body, "O link de redefinição é inválido ou expirou.")

    Clock.freeze(start)
    assert get(jar, "/passwords/#{token}/edit").status == 200
    Accounts.update_password(%{user | password_digest: Accounts.hash_password("another123", 4)})
    assert get(jar, "/passwords/#{token}/edit").location == "/passwords/new"
    assert get(jar, "/passwords/invalid/edit").location == "/passwords/new"
  end

  test "list shows entries and the total balance", %{jar: jar} do
    user = sign_in(jar)
    create_entry(user, cents: 15000)
    create_entry(user, kind: -1, cents: 4000)

    assert_contains(get(jar, "/").body, ["Saldo total", "R$ 110,00", "-R$ 40,00"])
  end

  test "list filters by day", %{jar: jar} do
    user = sign_in(jar)
    create_entry(user, date: "2026-10-26", cents: 1000)
    create_entry(user, date: "2026-10-27", cents: 2000)

    body = get(jar, "/current_accounts?date=2026-10-26").body
    assert_contains(body, ["Saldo do dia 26/10/2026", "R$ 10,00"])
    refute_contains(body, "R$ 20,00")
  end

  test "list paginates thirty entries per page", %{jar: jar} do
    user = sign_in(jar)
    for n <- 1..31, do: create_entry(user, historic: "entry #{n}.")

    first = get(jar, "/current_accounts").body
    assert_contains(first, "Mais antigos →")
    refute_contains(first, ["← Mais recentes", "entry 1."])
    second = get(jar, "/current_accounts?page=2").body
    assert_contains(second, ["← Mais recentes", "entry 1."])
    refute_contains(second, "Mais antigos →")
  end

  test "JSON has the jbuilder fields", %{jar: jar} do
    user = sign_in(jar)
    e = create_entry(user, historic: "Café/Almoço")

    want =
      ~s([{"id":#{e.id},"cash_account_id":5,"cost_id":6,"date_ocurrence":"2026-10-27","price":"150.0","historic":"Café/Almoço",) <>
        ~s("user_id":#{user.id},"type_launche":1,"url":"#{base_url()}/current_accounts/#{e.id}.json"}])

    assert get(jar, "/current_accounts.json").body == want
    assert get(jar, "/current_accounts/#{e.id}.json").body == String.slice(want, 1..-2//1)
    create_entry(user)
    assert get(jar, "/current_accounts.json").body =~ ~s("historic":null)
  end

  test "other users' entries are not found", %{jar: jar} do
    sign_in(jar)
    other = create_entry(create_user("other@example.com", "secret123"))
    path = "/current_accounts/#{other.id}"

    assert get(jar, path).status == 404
    assert get(jar, path <> "/edit").status == 404
    assert get(jar, path <> ".json").status == 404
    assert post(jar, path, [{"_method", "delete"}]).status == 404
    assert count("SELECT count(*) FROM current_accounts") == 1
  end

  defp valid_entry_form do
    [
      {"current_account[type_launche]", "credito"},
      {"current_account[price]", "150"},
      {"current_account[date_ocurrence]", "2026-10-27"},
      {"current_account[cost_id]", "6"},
      {"current_account[cash_account_id]", "5"},
      {"current_account[historic]", "Corridas do dia"}
    ]
  end

  test "create entry", %{jar: jar} do
    user = sign_in(jar)

    res = post(jar, "/current_accounts", valid_entry_form())

    assert res.location == "/current_accounts"
    assert_contains(get(jar, "/current_accounts").body, "Lançamento cadastrado.")
    assert count("SELECT count(*) FROM current_accounts WHERE user_id = $1 AND price = 150 AND type_launche = 1", [user.id]) == 1
  end

  test "create entry ignores a user id sent in the form", %{jar: jar} do
    user = sign_in(jar)
    other = create_user("other@example.com", "secret123")

    post(jar, "/current_accounts", valid_entry_form() ++ [{"current_account[user_id]", "#{other.id}"}])

    assert count("SELECT count(*) FROM current_accounts WHERE user_id = $1", [user.id]) == 1
  end

  test "create entry shows the validation messages", %{jar: jar} do
    sign_in(jar)

    res = post(jar, "/current_accounts", [{"current_account[price]", ""}])

    assert res.status == 422
    assert_contains(res.body, ["Valor não pode ficar em branco", "Tipo não está incluído na lista", ~s(<option value="">Selecione</option>)])
  end

  test "update entry", %{jar: jar} do
    e = create_entry(sign_in(jar))
    form = [{"_method", "patch"} | List.keyreplace(valid_entry_form(), "current_account[price]", 0, {"current_account[price]", "12.5"})]

    res = post(jar, "/current_accounts/#{e.id}", form)

    assert res.location == "/current_accounts/#{e.id}"
    assert_contains(get(jar, res.location).body, ["Lançamento atualizado.", "R$ 12,50"])
  end

  test "delete entry", %{jar: jar} do
    e = create_entry(sign_in(jar))

    res = post(jar, "/current_accounts/#{e.id}", [{"_method", "delete"}])

    assert res.status == 303
    assert_contains(get(jar, "/current_accounts").body, "Lançamento removido.")
    assert count("SELECT count(*) FROM current_accounts") == 0
  end

  test "legacy daily search redirects to the filter", %{jar: jar} do
    res = get(jar, "/search_account?date_calendar_now=2026-10-27")
    assert res.status == 301
    assert res.location == "/current_accounts?date=2026-10-27"
  end

  test "dashboard shows the daily and monthly balances", %{jar: jar} do
    user = sign_in(jar)
    create_entry(user, date: "2026-10-02", cents: 20000)
    create_entry(user, date: "2026-10-02", kind: -1, cost: 0, cents: 5000)
    create_entry(user, date: "2026-10-05", kind: -1, cost: 8, cents: 2000)
    create_entry(user, date: "2026-09-30", cents: 99900)

    body = get(jar, "/dashboard?month=2026-10").body

    assert_contains(body, ["Outubro de 2026", "Saldo Diário", "Saldo Mensal"])
    assert_in_order(body, ["05/10/2026", "-R$ 20,00", "02/10/2026", "R$ 150,00", "Total do mês", "R$ 130,00"])

    assert_in_order(body, ["Corridas", "R$ 200,00", "Combustível", "-R$ 50,00", "Lavagem", "-R$ 20,00", "Telefone", "R$ 0,00",
                           "Saldo do mês", "R$ 130,00"])

    refute_contains(body, "999")
  end

  test "dashboard links to the previous and next months", %{jar: jar} do
    sign_in(jar)
    assert_contains(get(jar, "/dashboard?month=2026-01").body, ["/dashboard?month=2025-12", "/dashboard?month=2026-02"])
  end

  test "dashboard falls back to the current month", %{jar: jar} do
    sign_in(jar)
    Clock.freeze(DateTime.new!(~D[2026-03-15], ~T[12:00:00], "America/Sao_Paulo"))
    assert_contains(get(jar, "/dashboard?month=bad").body, "Março de 2026")
  end

  test "health check and static files are served", %{jar: jar} do
    assert get(jar, "/up").status == 200
    assert get(jar, "/js/app.js").status == 200
    assert get(jar, "/icon.svg").status == 200
  end
end
