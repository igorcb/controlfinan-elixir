defmodule ControlFinan.FormatTest do
  use ExUnit.Case, async: true
  alias ControlFinan.Format

  test "currency formats like Rails in Portuguese" do
    for {cents, want} <- [{123_450, "R$ 1.234,50"}, {-1250, "-R$ 12,50"}, {0, "R$ 0,00"}, {5, "R$ 0,05"}, {123_456_789, "R$ 1.234.567,89"}] do
      assert Format.currency(cents) == want
    end
  end

  test "decimal text prints like Ruby BigDecimal" do
    for {cents, want} <- [{15000, "150.0"}, {1250, "12.5"}, {5, "0.05"}, {1234, "12.34"}, {-1250, "-12.5"}] do
      assert Format.decimal_text(cents) == want
    end
  end

  test "to_cents reads Postgres numeric values" do
    for {text, want} <- [{"150.00", 15000}, {"-12.5", -1250}, {"0", 0}, {"7.05", 705}] do
      assert Format.to_cents(Decimal.new(text)) == want
    end
  end
end
