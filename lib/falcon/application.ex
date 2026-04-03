defmodule Falcon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FalconWeb.Telemetry,
      Falcon.Repo,
      {DNSCluster, query: Application.get_env(:falcon, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Falcon.PubSub},
      {Registry, keys: :unique, name: Falcon.ThreadRegistry},
      {DynamicSupervisor, name: Falcon.ThreadSupervisor, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      FalconWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Falcon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FalconWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
