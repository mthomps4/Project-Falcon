defmodule Falcon.Chat.Thread do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "threads" do
    field :title, :string
    field :model, :string
    field :system_prompt, :string
    field :status, :string, default: "idle"
    field :archived_at, :utc_datetime

    # Folder-scoped agent mode
    field :scoped_paths, {:array, :string}, default: []
    field :allowed_tools, {:array, :string}, default: []

    # Model parameters (temperature, top_p, etc.)
    field :parameters, :map, default: %{}

    belongs_to :user, Falcon.Accounts.User
    belongs_to :provider, Falcon.Providers.Provider
    has_many :messages, Falcon.Chat.Message

    timestamps(type: :utc_datetime)
  end

  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [
      :title,
      :model,
      :system_prompt,
      :status,
      :archived_at,
      :scoped_paths,
      :allowed_tools,
      :parameters,
      :user_id,
      :provider_id
    ])
    |> validate_required([:model, :user_id])
  end
end
