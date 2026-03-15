defmodule ExCortex.Core.Registry do
  @moduledoc """
  Unified registry over code modules and DB-defined neuron resources.
  DB overrides code (closer to runtime wins).
  """

  use GenServer

  import Ecto.Query

  alias ExCortex.Core.Registry.CodeResource
  alias ExCortex.Core.Registry.DBResource
  alias ExCortex.Neurons.Neuron

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register_code(type, module) do
    GenServer.call(__MODULE__, {:register_code, type, module})
  end

  def register_db(%Neuron{} = rd) do
    GenServer.call(__MODULE__, {:register_db, rd})
  end

  def list(type, opts \\ []) do
    GenServer.call(__MODULE__, {:list, type, opts})
  end

  def get(type, name) do
    GenServer.call(__MODULE__, {:get, type, name})
  end

  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  @impl true
  def init(_opts) do
    {:ok, %{code: %{}, db: %{}}, {:continue, :load_db}}
  end

  @impl true
  def handle_continue(:load_db, state) do
    case load_db_resources() do
      {:ok, db_resources} ->
        {:noreply, %{state | db: db_resources}}

      :repo_not_ready ->
        Process.send_after(self(), :retry_load_db, 200)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:retry_load_db, state) do
    case load_db_resources() do
      {:ok, db_resources} ->
        {:noreply, %{state | db: db_resources}}

      :repo_not_ready ->
        Process.send_after(self(), :retry_load_db, 200)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:register_code, type, module}, _from, state) do
    resource = CodeResource.wrap(type, module)
    code = Map.update(state.code, type, [resource], &[resource | &1])
    {:reply, :ok, %{state | code: code}}
  end

  def handle_call({:register_db, rd}, _from, state) do
    resource = DBResource.wrap(rd)
    type = resource.type
    db = Map.update(state.db, type, [resource], &[resource | &1])
    {:reply, :ok, %{state | db: db}}
  end

  def handle_call({:list, type, opts}, _from, state) do
    status = Keyword.get(opts, :status)
    resources = merge(type, state)
    filtered = if status, do: Enum.filter(resources, &(&1.status == status)), else: resources
    {:reply, filtered, state}
  end

  def handle_call({:get, type, name}, _from, state) do
    result = type |> merge(state) |> Enum.find(&(&1.name == name))
    {:reply, result, state}
  end

  def handle_call(:reload, _from, state) do
    db_resources =
      case load_db_resources() do
        {:ok, resources} -> resources
        :repo_not_ready -> state.db
      end

    {:reply, :ok, %{state | db: db_resources}}
  end

  defp merge(type, state) do
    code = Map.get(state.code, type, [])
    db = Map.get(state.db, type, [])
    db_names = MapSet.new(db, & &1.name)
    not_overridden = Enum.reject(code, &MapSet.member?(db_names, &1.name))
    db ++ not_overridden
  end

  defp load_db_resources do
    if Application.get_env(:ex_cortex, :sql_sandbox, false) do
      {:ok, %{}}
    else
      try do
        resources =
          from(r in Neuron, where: r.status != "archived")
          |> ExCortex.Repo.all()
          |> Enum.map(&DBResource.wrap/1)
          |> Enum.group_by(& &1.type)

        {:ok, resources}
      rescue
        _ -> :repo_not_ready
      end
    end
  end
end
