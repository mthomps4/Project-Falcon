defmodule Falcon.Providers.Provider do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "providers" do
    field :name, :string
    field :type, :string
    field :base_url, :string
    field :api_key, :string
    field :enabled, :boolean, default: true
    field :config, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :type, :base_url, :api_key, :enabled, :config])
    |> validate_required([:name, :type, :base_url])
    |> validate_inclusion(:type, ["ollama", "openai"])
    |> unique_constraint(:name)
  end
end
