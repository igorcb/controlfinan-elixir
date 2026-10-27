defmodule ControlFinanWeb.Templates do
  @moduledoc """
  Plain EEx templates (not HEEx), so the HTML comes out exactly as written: same attribute order as the Rails app.
  Dynamic text goes through `h/1`.
  """
  require EEx
  import ControlFinan.Format, only: [currency: 1, amount_class: 1]
  import ControlFinan.Entries,
    only: [costs: 0, cash_accounts: 0, persisted?: 1, credit?: 1, name_account: 1, name_cost: 1, date_br: 1, day_month: 1, date_iso: 1,
           type_name: 1, signed_cents: 1, historic_text: 1, price_field: 1]

  @dir Path.join(__DIR__, "templates")

  @titles %{
    "sessions_new" => "Entrar",
    "registrations_new" => "Criar conta",
    "passwords_new" => "Recuperar senha",
    "passwords_edit" => "Nova senha",
    "current_accounts_index" => "Conta Corrente",
    "current_accounts_new" => "Novo lançamento",
    "current_accounts_edit" => "Editar lançamento",
    "current_accounts_show" => "Lançamento",
    "dashboards_show" => "Dashboard"
  }

  def h(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  for file <- File.ls!(@dir), String.ends_with?(file, ".html.eex") do
    @external_resource Path.join(@dir, file)
  end

  EEx.function_from_file(:defp, :layout, Path.join(@dir, "layout.html.eex"), [:assigns])
  EEx.function_from_file(:def, :form, Path.join(@dir, "_form.html.eex"), [:assigns])
  EEx.function_from_file(:def, :errors, Path.join(@dir, "_errors.html.eex"), [:errors])
  EEx.function_from_file(:def, :amounts, Path.join(@dir, "_amounts.html.eex"), [:header, :rows, :total_label, :total])

  for {page, _title} <- @titles do
    EEx.function_from_file(:defp, :"page_#{page}", Path.join(@dir, page <> ".html.eex"), [:assigns])
  end

  @doc "Renders a page inside the layout."
  def render(page, assigns) do
    content = page_content(page, assigns)
    layout(Map.merge(assigns, %{title: Map.fetch!(@titles, page), content: content}))
  end

  for {page, _title} <- @titles do
    defp page_content(unquote(page), assigns), do: unquote(:"page_#{page}")(assigns)
  end
end
