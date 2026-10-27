defmodule ControlFinan.Mailer do
  @moduledoc "Delivers the password reset e-mail. The default one writes it to the log."
  @callback deliver(to :: String.t(), subject :: String.t(), text :: String.t()) :: :ok | {:error, term}

  def deliver(to, subject, text), do: Application.get_env(:controlfinan, :mailer, ControlFinan.LogMailer).deliver(to, subject, text)
end

defmodule ControlFinan.LogMailer do
  @behaviour ControlFinan.Mailer
  require Logger

  @impl true
  def deliver(to, subject, text) do
    Logger.warning("mail to=#{to} subject=#{inspect(subject)}\n#{text}")
    :ok
  end
end
