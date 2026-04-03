defmodule Falcon.Providers do
  @moduledoc """
  Context for managing LLM providers.
  """
  import Ecto.Query
  alias Falcon.Repo
  alias Falcon.Providers.Provider

  def list_providers do
    Provider
    |> where([p], p.enabled == true)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  def get_provider!(id), do: Repo.get!(Provider, id)

  def create_provider(attrs) do
    %Provider{}
    |> Provider.changeset(attrs)
    |> Repo.insert()
  end

  def update_provider(%Provider{} = provider, attrs) do
    provider
    |> Provider.changeset(attrs)
    |> Repo.update()
  end

  def delete_provider(%Provider{} = provider) do
    Repo.delete(provider)
  end

  def ensure_default_ollama! do
    case Repo.get_by(Provider, name: "Local Ollama") do
      nil ->
        create_provider(%{
          name: "Local Ollama",
          type: "ollama",
          base_url: Application.get_env(:falcon, :ollama_url, "http://localhost:11434")
        })

      provider ->
        {:ok, provider}
    end
  end
end
