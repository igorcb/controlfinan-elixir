defmodule ControlFinan.FakeMailer do
  @moduledoc "Keeps the sent e-mails as \"to|subject|text\"."
  @behaviour ControlFinan.Mailer
  use Agent

  def start_link, do: Agent.start_link(fn -> [] end, name: __MODULE__)
  def reset, do: Agent.update(__MODULE__, fn _ -> [] end)
  def sent, do: Agent.get(__MODULE__, &Enum.reverse/1)

  @impl true
  def deliver(to, subject, text), do: Agent.update(__MODULE__, &[to <> "|" <> subject <> "|" <> text | &1])
end
