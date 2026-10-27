defmodule ControlFinan.ModelsTest do
  use ControlFinan.AppCase
  alias ControlFinan.Entries.Entry

  test "user password uses the Rails bcrypt format" do
    user = %Accounts.User{password_digest: Accounts.hash_password("secret123", 4)}
    assert String.starts_with?(user.password_digest, "$2a$")
    assert Accounts.check_password?(user, "secret123")
    refute Accounts.check_password?(user, "wrong")
  end

  test "user accepts a digest written by Rails" do
    # Digest of "benchmark123" written by the Rails app (has_secure_password, bcrypt-ruby) for its benchmark account.
    user = %Accounts.User{password_digest: "$2a$12$xUBQqXOC4yO3ZUCU3U./FeJ/CU4pqmbNxFQ5iUUrWzLWmKSpUKChe"}
    assert Accounts.check_password?(user, "benchmark123")
    refute Accounts.check_password?(user, "wrong")
  end

  test "validate user returns the Rails messages" do
    create_user("taken@example.com", "secret123")

    {_, errors} = Accounts.validate(%Accounts.User{}, "", "")
    assert Enum.join(errors, "|") == "Senha não pode ficar em branco|E-mail não pode ficar em branco"

    {_, errors} = Accounts.validate(%Accounts.User{email_address: "bad"}, "123", "456")

    assert Enum.join(errors, "|") ==
             "Confirmação da senha não é igual a Senha|E-mail não é válido|Senha é muito curto (mínimo: 6 caracteres)"

    {_, errors} = Accounts.validate(%Accounts.User{email_address: " TAKEN@example.com "}, "secret123", "secret123")
    assert Enum.join(errors, "|") == "E-mail já está em uso"
  end

  test "entry validate returns the Rails messages" do
    assert Enum.join(Entries.validate(%Entry{}), "|") ==
             "Tipo não está incluído na lista|Conta não está incluído na lista|Categoria não está incluído na lista|" <>
               "Data não pode ficar em branco|Valor não pode ficar em branco|Valor não é um número"

    e = %Entry{cash_account_id: 0, cost_id: 0, type_launche: -1, date: ~D[2026-10-27], price_set: true, price_cents: 0}
    assert Enum.join(Entries.validate(e), "|") == "Valor deve ser maior que 0"

    e = %Entry{cash_account_id: 99, cost_id: 99, type_launche: 1, date: ~D[2026-10-27], price_text: "abc"}

    assert Enum.join(Entries.validate(e), "|") ==
             "Conta não está incluído na lista|Categoria não está incluído na lista|Valor não é um número"
  end

  test "entry names with fallback" do
    e = %Entry{cash_account_id: 1, cost_id: 99, type_launche: -1, price_cents: 1000}
    assert Entries.name_account(e) == "Itaú"
    assert Entries.name_cost(e) == "Não definido"
    assert Entries.type_name(e) == "Débito"
    assert Entries.signed_cents(e) == -1000
  end

  test "balance is credits minus debits" do
    user = create_user("driver@example.com", "secret123")
    create_entry(user, cents: 15000)
    create_entry(user, kind: -1, cents: 4050)
    assert Entries.balance(user.id, nil) == 10950
  end

  test "summarize month groups by day and discounts ride expenses" do
    user = create_user("driver@example.com", "secret123")
    create_entry(user, date: "2026-10-02", cents: 20000)
    create_entry(user, date: "2026-10-02", kind: -1, cost: 0, cents: 5000)
    create_entry(user, date: "2026-10-05", kind: -1, cost: 8, cents: 2000)
    create_entry(user, date: "2026-09-30", cents: 99900)

    s = Entries.summarize_month(user.id, ~D[2026-10-01])
    assert s.daily == [{"05/10/2026", -2000}, {"02/10/2026", 15000}]
    assert s.month_balance == 13000
    assert s.monthly == [{"Corridas", 20000}, {"Combustível", -5000}, {"Lavagem", -2000}, {"Telefone", 0}]
    assert s.rides_net == 13000
  end
end
