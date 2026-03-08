defmodule ExCellenceServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias ExCellenceServer.Sources.SourceSupervisor

  @impl true
  def start(_type, _args) do
    # SaladUI requires TwMerge.Cache ETS table
    if :ets.whereis(:tw_merge_cache) == :undefined do
      TwMerge.Cache.create_table()
      TwMerge.Cache.insert(:class_tree, TwMerge.ClassTree.generate())
    end

    children = [
      ExCellenceServerWeb.Telemetry,
      ExCellenceServer.Repo,
      {DNSCluster, query: Application.get_env(:ex_cellence_server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ExCellenceServer.PubSub},
      {Registry, keys: :unique, name: ExCellenceServer.SourceRegistry},
      {Task.Supervisor, name: ExCellenceServer.SourceTaskSupervisor},
      SourceSupervisor,
      {Task, fn -> SourceSupervisor.start_all_active() end},
      ExCellenceServer.ScheduledQuestRunner,
      ExCellenceServerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExCellenceServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ExCellenceServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
