defmodule Falcon.Repo.Migrations.CreateChatTables do
  use Ecto.Migration

  def change do
    create table(:threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :model, :string, null: false
      add :system_prompt, :text
      add :status, :string, default: "idle", null: false
      add :archived_at, :utc_datetime

      # Folder-scoped agent mode
      add :scoped_paths, {:array, :string}, default: []
      add :allowed_tools, {:array, :string}, default: []

      # Model parameters
      add :parameters, :map, default: %{}

      # Provider reference
      add :provider_id, references(:providers, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:threads, [:user_id])
    create index(:threads, [:status])

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false
      add :content, :text, null: false
      add :parent_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :metadata, :map, default: %{}

      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:thread_id])
    create index(:messages, [:parent_id])

    create table(:attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer
      add :storage_path, :string, null: false

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:attachments, [:message_id])
  end
end
