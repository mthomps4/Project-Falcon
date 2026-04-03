defmodule Falcon.Repo.Migrations.CreateProviders do
  use Ecto.Migration

  def change do
    create table(:providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false
      add :base_url, :string, null: false
      add :api_key, :text
      add :enabled, :boolean, default: true, null: false
      add :config, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:providers, [:name])
  end
end
