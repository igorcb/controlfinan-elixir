defmodule ControlFinanWeb.Router do
  use Phoenix.Router, helpers: false
  alias ControlFinanWeb.{DashboardController, EntryController, MiscController, PasswordController}
  alias ControlFinanWeb.{RegistrationController, SessionController}

  get "/up", MiscController, :up

  get "/session/new", SessionController, :new
  post "/session", SessionController, :create
  delete "/session", SessionController, :delete
  get "/registration/new", RegistrationController, :new
  post "/registration", RegistrationController, :create
  get "/passwords/new", PasswordController, :new
  post "/passwords", PasswordController, :create
  get "/passwords/:token/edit", PasswordController, :edit
  put "/passwords/:token", PasswordController, :update
  patch "/passwords/:token", PasswordController, :update

  get "/", EntryController, :index
  get "/current_accounts", EntryController, :index
  get "/current_accounts.json", EntryController, :index
  post "/current_accounts", EntryController, :create
  get "/current_accounts/new", EntryController, :new
  get "/current_accounts/:id", EntryController, :show
  get "/current_accounts/:id/edit", EntryController, :edit
  put "/current_accounts/:id", EntryController, :update
  patch "/current_accounts/:id", EntryController, :update
  delete "/current_accounts/:id", EntryController, :delete
  get "/dashboard", DashboardController, :show

  # Legacy daily balance search, now a filter on the listing.
  get "/search_account", MiscController, :search_account

  match :*, "/*path", MiscController, :not_found
end
