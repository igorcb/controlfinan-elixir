defmodule ControlFinan.Format do
  @moduledoc "Money is kept in cents (integers) so no floating point is involved."

  @doc ~S|Formats like Rails number_to_currency in pt-BR: "R$ 1.234,50"; negatives as "-R$ 1.234,50".|
  def currency(cents) when cents < 0, do: "-" <> currency(-cents)

  def currency(cents) do
    units = Integer.to_string(div(cents, 100))
    "R$ " <> group(units) <> "," <> pad2(rem(cents, 100))
  end

  defp group(units) do
    units
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(".", &Enum.join/1)
    |> String.reverse()
  end

  @doc "The color of an amount: red when negative, green otherwise."
  def amount_class(cents) when cents < 0, do: "text-red-700"
  def amount_class(_cents), do: "text-emerald-700"

  @doc ~S|Prints cents like Ruby's BigDecimal#to_s: 15000 -> "150.0", 1250 -> "12.5", 5 -> "0.05".|
  def decimal_text(cents) when cents < 0, do: "-" <> decimal_text(-cents)

  def decimal_text(cents) do
    fraction =
      case String.trim_trailing(pad2(rem(cents, 100)), "0") do
        "" -> "0"
        f -> f
      end

    Integer.to_string(div(cents, 100)) <> "." <> fraction
  end

  @doc "Converts a Postgres numeric (Decimal) into cents."
  def to_cents(nil), do: 0

  def to_cents(%Decimal{} = value) do
    value |> Decimal.mult(100) |> Decimal.round(0, :half_up) |> Decimal.to_integer()
  end

  @doc "Converts cents into a Decimal with two places, for the numeric(9,2) column."
  def from_cents(cents), do: Decimal.div(Decimal.new(cents), 100)

  defp pad2(value) when value < 10, do: "0" <> Integer.to_string(value)
  defp pad2(value), do: Integer.to_string(value)
end
