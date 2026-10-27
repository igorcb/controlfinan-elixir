defmodule ControlFinan.Clock do
  @moduledoc "The current time. Tests can freeze it with `freeze/1`."

  def now do
    case :persistent_term.get({__MODULE__, :frozen}, nil) do
      nil -> DateTime.utc_now()
      frozen -> frozen
    end
  end

  def freeze(%DateTime{} = at), do: :persistent_term.put({__MODULE__, :frozen}, DateTime.shift_zone!(at, "Etc/UTC"))
  def unfreeze, do: :persistent_term.erase({__MODULE__, :frozen})

  def unix, do: DateTime.to_unix(now())

  @doc "Today's date in the app time zone (America/Sao_Paulo)."
  def today do
    now() |> DateTime.shift_zone!(Application.get_env(:controlfinan, :time_zone, "America/Sao_Paulo")) |> DateTime.to_date()
  end
end
