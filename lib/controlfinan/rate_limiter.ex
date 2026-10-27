defmodule ControlFinan.RateLimiter do
  @moduledoc "Works like Rails `rate_limit to: 10, within: 3.minutes`: a counter per action and IP, in memory."
  use GenServer

  alias ControlFinan.Clock

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def reset, do: GenServer.call(__MODULE__, :reset)

  def allow?(key, to, within_seconds), do: GenServer.call(__MODULE__, {:hit, key, to, within_seconds})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:reset, _from, _state), do: {:reply, :ok, %{}}

  def handle_call({:hit, key, to, within}, _from, state) do
    now = DateTime.to_unix(Clock.now(), :microsecond)

    {count, reset_at} =
      case Map.get(state, key) do
        {count, reset_at} when now <= reset_at -> {count, reset_at}
        _ -> {0, now + within * 1_000_000}
      end

    {:reply, count + 1 <= to, Map.put(state, key, {count + 1, reset_at})}
  end
end
