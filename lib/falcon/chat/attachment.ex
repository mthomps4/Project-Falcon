defmodule Falcon.Chat.Attachment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "attachments" do
    field :filename, :string
    field :content_type, :string
    field :size, :integer
    field :storage_path, :string

    belongs_to :message, Falcon.Chat.Message

    timestamps(type: :utc_datetime)
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:filename, :content_type, :size, :storage_path, :message_id])
    |> validate_required([:filename, :content_type, :storage_path, :message_id])
  end
end
