defmodule Falcon.LLM.ProviderRegistry do
  @moduledoc """
  Registry for LLM provider instances. Maps provider types to their modules
  and manages configured provider instances stored in the database.
  """

  @provider_modules %{
    "ollama" => Falcon.LLM.Ollama,
    "openai" => Falcon.LLM.OpenAI
  }

  @doc "Get the provider module for a given type string."
  def module_for(type) when is_binary(type) do
    Map.get(@provider_modules, type)
  end

  @doc "List all registered provider type keys."
  def provider_types do
    Map.keys(@provider_modules)
  end

  @doc "Build a config map from a database provider record."
  def config_for(provider) do
    %{base_url: provider.base_url, api_key: provider.api_key}
  end

  def list_all_models do
    providers = Falcon.Providers.list_providers()

    providers
    |> Task.async_stream(
      fn provider ->
        module = module_for(provider.type)

        if module do
          config = config_for(provider)

          case module.list_models(config) do
            {:ok, models} ->
              Enum.map(models, fn m ->
                Map.merge(m, %{provider_id: provider.id, provider_name: provider.name})
              end)

            {:error, _} ->
              []
          end
        else
          []
        end
      end,
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, models} -> models
      _ -> []
    end)
  end
end
