defmodule ControlFinan.MixProject do
  use Mix.Project

  def project do
    [
      app: :controlfinan,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: [test: ["ecto.create --quiet", "test"]],
      deps: deps(),
      releases: [controlfinan: [include_executables_for: [:unix]]]
    ]
  end

  def application do
    [mod: {ControlFinan.Application, []}, extra_applications: [:logger, :crypto]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:bandit, "~> 1.5"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19"},
      {:jason, "~> 1.4"},
      {:bcrypt_elixir, "~> 3.2"},
      {:tz, "~> 0.28"}
    ]
  end
end
