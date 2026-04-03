defmodule Falcon.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field :role, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :thread, Falcon.Chat.Thread
    belongs_to :parent, __MODULE__
    has_many :attachments, Falcon.Chat.Attachment

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :metadata, :thread_id, :parent_id])
    |> validate_required([:role, :content, :thread_id])
    |> validate_inclusion(:role, ["user", "assistant", "system", "tool"])
  end
end
