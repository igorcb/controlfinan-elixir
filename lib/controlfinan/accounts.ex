defmodule ControlFinan.Accounts do
  @moduledoc "Users (has_secure_password), sessions and their validations, like the Rails app."
  alias ControlFinan.Repo

  defmodule User do
    defstruct id: nil, email_address: "", password_digest: ""
  end

  # Same regexp as Ruby's URI::MailTo::EMAIL_REGEXP.
  @email_regexp ~r/\A[a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\z/

  def normalize_email(value), do: value |> String.trim() |> String.downcase()

  defp cost, do: Application.get_env(:controlfinan, :bcrypt_cost, 12)

  @doc "A bcrypt digest in the same \"$2a$\" format as Rails (bcrypt_elixir writes \"$2b$\" unless asked for the legacy prefix)."
  def hash_password(raw, cost \\ cost()) do
    Bcrypt.Base.hash_password(truncate72(raw), Bcrypt.Base.gen_salt(cost, true))
  end

  def check_password?(%User{password_digest: digest}, raw) when is_binary(raw) and raw != "" do
    Bcrypt.verify_pass(truncate72(raw), digest)
  end

  def check_password?(_user, _raw), do: false

  # bcrypt only uses the first 72 bytes, like Rails.
  defp truncate72(raw) when byte_size(raw) > 72, do: binary_part(raw, 0, 72)
  defp truncate72(raw), do: raw

  @doc "Spent when the e-mail does not exist, so both cases take the same time."
  def prepare_dummy, do: :persistent_term.put({__MODULE__, :dummy}, %User{password_digest: hash_password("dummy-password")})
  def burn_time, do: check_password?(:persistent_term.get({__MODULE__, :dummy}), "x")

  @doc "Returns {normalized user, messages} with the Rails messages (pt-BR) in the same order."
  def validate(%User{} = user, password, confirmation) do
    errors = []
    errors = if password in [nil, ""], do: errors ++ ["Senha não pode ficar em branco"], else: errors

    errors =
      if password != nil and confirmation != nil and password != confirmation,
        do: errors ++ ["Confirmação da senha não é igual a Senha"],
        else: errors

    user = %{user | email_address: normalize_email(user.email_address)}

    errors =
      cond do
        user.email_address == "" -> errors ++ ["E-mail não pode ficar em branco"]
        not Regex.match?(@email_regexp, user.email_address) -> errors ++ ["E-mail não é válido"]
        email_taken?(user) -> errors ++ ["E-mail já está em uso"]
        true -> errors
      end

    errors =
      if password not in [nil, ""] and length(String.to_charlist(password)) < 6,
        do: errors ++ ["Senha é muito curto (mínimo: 6 caracteres)"],
        else: errors

    {user, errors}
  end

  defp email_taken?(user) do
    %{rows: [[exists]]} =
      Repo.query!("SELECT EXISTS (SELECT 1 FROM users WHERE email_address = $1 AND id <> $2)", [user.email_address, user.id || 0])

    exists
  end

  defp to_user([id, email, digest]), do: %User{id: id, email_address: email, password_digest: digest}

  defp one(sql, args) do
    case Repo.query!(sql, args) do
      %{rows: [row]} -> to_user(row)
      _ -> nil
    end
  end

  def find_by_email(email),
    do: one("SELECT id, email_address, password_digest FROM users WHERE email_address = $1", [normalize_email(email)])

  def find(id), do: one("SELECT id, email_address, password_digest FROM users WHERE id = $1", [id])

  def create(%User{} = user) do
    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO users (email_address, password_digest, created_at, updated_at) VALUES ($1, $2, now(), now()) RETURNING id",
        [user.email_address, user.password_digest]
      )

    %{user | id: id}
  end

  def update_password(%User{} = user) do
    Repo.query!("UPDATE users SET password_digest = $1, updated_at = now() WHERE id = $2", [user.password_digest, user.id])
    user
  end

  # Sessions, like Rails 8's authentication generator.

  def session_user(session_id) do
    case Repo.query!(
           "SELECT u.id, u.email_address, u.password_digest FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.id = $1",
           [session_id]
         ) do
      %{rows: [row]} -> to_user(row)
      _ -> nil
    end
  end

  def create_session(%User{id: user_id}, user_agent, ip) do
    user_agent = if byte_size(user_agent) > 255, do: binary_part(user_agent, 0, 255), else: user_agent

    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO sessions (user_id, user_agent, ip_address, created_at, updated_at) VALUES ($1, $2, $3, now(), now()) RETURNING id",
        [user_id, user_agent, ip]
      )

    id
  end

  def delete_session(id), do: Repo.query!("DELETE FROM sessions WHERE id = $1", [id])
  def delete_sessions_of(%User{id: id}), do: Repo.query!("DELETE FROM sessions WHERE user_id = $1", [id])
end
