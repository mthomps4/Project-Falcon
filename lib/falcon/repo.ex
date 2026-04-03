defmodule Falcon.Repo do
  use Ecto.Repo,
    otp_app: :falcon,
    adapter: Ecto.Adapters.Postgres
end
