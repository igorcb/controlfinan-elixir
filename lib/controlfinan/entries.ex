defmodule ControlFinan.Entries do
  @moduledoc "Rows of current_accounts (credits and debits), their validations and the dashboard numbers."
  alias ControlFinan.{Format, Repo}

  @cash_accounts [
    {0, "Conta Dinheiro"}, {1, "Itaú"}, {2, "Santander"}, {3, "CEF Poupança"}, {4, "PagSeguro"},
    {5, "Uber"}, {6, "Platinum Itaú"}, {7, "Banco do Brasil"}, {8, "99Pop"}
  ]

  @costs [
    {0, "Combustível"}, {1, "Central"}, {2, "Aluguel Carro"}, {3, "Almoço"}, {4, "Lanche"}, {5, "Diversos"},
    {6, "Corridas"}, {7, "Telefone"}, {8, "Lavagem"}, {9, "Transferência"}, {10, "Depósitos"},
    {11, "Estacionamento"}, {12, "Impostos"}, {13, "Multas"}, {14, "Manutenção"}, {15, "Viagens Uber"}
  ]

  @debit -1
  @credit 1
  @rides 6
  # Unset marks an integer form field that was blank or invalid.
  @unset -1
  # Discounted from the rides in the monthly balance (legacy dashboard rule), in this order.
  @ride_expenses [{0, "Combustível"}, {8, "Lavagem"}, {7, "Telefone"}]

  def cash_accounts, do: @cash_accounts
  def costs, do: @costs
  def debit, do: @debit
  def credit, do: @credit
  def rides, do: @rides
  def unset, do: @unset

  defmodule Entry do
    defstruct id: nil, user_id: nil, cash_account_id: -1, cost_id: -1, type_launche: 0, date: nil,
              price_cents: 0, price_set: false, price_text: "", historic: nil
  end

  def option_name(options, id) do
    case List.keyfind(options, id, 0) do
      {_, name} -> name
      nil -> "Não definido"
    end
  end

  defp option?(options, id), do: List.keymember?(options, id, 0)

  def persisted?(%Entry{id: id}), do: id != nil
  def credit?(%Entry{type_launche: t}), do: t == @credit
  def name_account(e), do: option_name(@cash_accounts, e.cash_account_id)
  def name_cost(e), do: option_name(@costs, e.cost_id)
  def date_br(%Entry{date: d}), do: Calendar.strftime(d, "%d/%m/%Y")
  def day_month(%Entry{date: d}), do: Calendar.strftime(d, "%d/%m")
  def date_iso(%Entry{date: nil}), do: ""
  def date_iso(%Entry{date: d}), do: Date.to_iso8601(d)
  def type_name(e), do: if(credit?(e), do: "Crédito", else: "Débito")
  def signed_cents(e), do: if(credit?(e), do: e.price_cents, else: -e.price_cents)
  def historic_text(%Entry{historic: h}), do: h || ""

  @doc "The value shown in the form: the decimal like Rails, or what the user typed."
  def price_field(%Entry{price_set: true, price_cents: c}), do: Format.decimal_text(c)
  def price_field(%Entry{price_text: t}), do: t

  @doc "The Rails messages (pt-BR) in the same order as the model validations."
  def validate(%Entry{} = e) do
    [
      e.type_launche not in [@debit, @credit] && "Tipo não está incluído na lista",
      not option?(@cash_accounts, e.cash_account_id) && "Conta não está incluído na lista",
      not option?(@costs, e.cost_id) && "Categoria não está incluído na lista",
      e.date == nil && "Data não pode ficar em branco"
    ]
    |> Enum.filter(& &1)
    |> Kernel.++(price_errors(e))
  end

  # Like Rails presence + numericality: a blank value is also "not a number".
  defp price_errors(%Entry{price_set: false, price_text: ""}), do: ["Valor não pode ficar em branco", "Valor não é um número"]
  defp price_errors(%Entry{price_set: false}), do: ["Valor não é um número"]
  defp price_errors(%Entry{price_cents: c}) when c <= 0, do: ["Valor deve ser maior que 0"]
  defp price_errors(_), do: []

  @columns "id, user_id, cash_account_id, cost_id, type_launche, date_ocurrence, price, historic"

  defp to_entry([id, user_id, cash, cost, type, date, price, historic]) do
    %Entry{id: id, user_id: user_id, cash_account_id: cash, cost_id: cost, type_launche: type, date: date,
           price_cents: Format.to_cents(price), price_set: true, historic: historic}
  end

  defp day_filter(nil, sql, args), do: {sql, args}
  defp day_filter(day, sql, args), do: {sql <> " AND date_ocurrence = $2", args ++ [day]}

  @doc "Up to `limit` entries, most recent first, optionally on one day."
  def list(user_id, day, limit, offset) do
    {sql, args} = day_filter(day, "SELECT #{@columns} FROM current_accounts WHERE user_id = $1", [user_id])
    sql = sql <> " ORDER BY date_ocurrence DESC, id DESC LIMIT #{limit} OFFSET #{offset}"
    Repo.query!(sql, args).rows |> Enum.map(&to_entry/1)
  end

  @doc "Credits minus debits: the sign comes from type_launche (-1 or 1)."
  def balance(user_id, day) do
    {sql, args} = day_filter(day, "SELECT COALESCE(SUM(price * type_launche), 0) FROM current_accounts WHERE user_id = $1", [user_id])
    %{rows: [[total]]} = Repo.query!(sql, args)
    Format.to_cents(total)
  end

  def find(user_id, id) do
    case Repo.query!("SELECT #{@columns} FROM current_accounts WHERE user_id = $1 AND id = $2", [user_id, id]) do
      %{rows: [row]} -> to_entry(row)
      _ -> nil
    end
  end

  def save(%Entry{id: nil} = e) do
    %{rows: [[id]]} =
      Repo.query!(
        """
        INSERT INTO current_accounts
        (user_id, cash_account_id, cost_id, type_launche, date_ocurrence, price, historic, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, now(), now()) RETURNING id
        """,
        [e.user_id, e.cash_account_id, e.cost_id, e.type_launche, e.date, Format.from_cents(e.price_cents), e.historic]
      )

    %{e | id: id}
  end

  def save(%Entry{} = e) do
    Repo.query!(
      """
      UPDATE current_accounts SET cash_account_id = $1, cost_id = $2, type_launche = $3,
      date_ocurrence = $4, price = $5, historic = $6, updated_at = now() WHERE id = $7 AND user_id = $8
      """,
      [e.cash_account_id, e.cost_id, e.type_launche, e.date, Format.from_cents(e.price_cents), e.historic, e.id, e.user_id]
    )

    e
  end

  def delete(%Entry{} = e), do: Repo.query!("DELETE FROM current_accounts WHERE id = $1 AND user_id = $2", [e.id, e.user_id])

  @doc """
  The dashboard numbers of one month: `daily` (balance of each day, most recent first, as {label, cents}),
  `month_balance`, `monthly` (rides, then each ride expense as a negative amount) and `rides_net`.
  """
  def summarize_month(user_id, %Date{} = month) do
    first = Date.beginning_of_month(month)
    last = Date.end_of_month(month)

    daily =
      Repo.query!(
        """
        SELECT date_ocurrence, SUM(price * type_launche) FROM current_accounts
        WHERE user_id = $1 AND date_ocurrence BETWEEN $2 AND $3 GROUP BY date_ocurrence ORDER BY date_ocurrence DESC
        """,
        [user_id, first, last]
      ).rows
      |> Enum.map(fn [day, total] -> {Calendar.strftime(day, "%d/%m/%Y"), Format.to_cents(total)} end)

    expenses =
      Repo.query!(
        """
        SELECT cost_id, SUM(price) FROM current_accounts
        WHERE user_id = $1 AND date_ocurrence BETWEEN $2 AND $3 AND cost_id = ANY($4) GROUP BY cost_id
        """,
        [user_id, first, last, [0, 8, 7]]
      ).rows
      |> Map.new(fn [cost_id, total] -> {cost_id, Format.to_cents(total)} end)

    %{rows: [[rides]]} =
      Repo.query!(
        """
        SELECT COALESCE(SUM(price * type_launche), 0) FROM current_accounts
        WHERE user_id = $1 AND date_ocurrence BETWEEN $2 AND $3 AND cost_id = $4
        """,
        [user_id, first, last, @rides]
      )

    rides = Format.to_cents(rides)
    expense_rows = Enum.map(@ride_expenses, fn {id, name} -> {name, -Map.get(expenses, id, 0)} end)

    %{
      daily: daily,
      month_balance: daily |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
      monthly: [{"Corridas", rides} | expense_rows],
      rides_net: rides + (expense_rows |> Enum.map(&elem(&1, 1)) |> Enum.sum())
    }
  end
end
