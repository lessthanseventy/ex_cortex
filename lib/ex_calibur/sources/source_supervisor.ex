defmodule ExCalibur.Sources.SourceSupervisor do
  @moduledoc false
  use DynamicSupervisor

  alias ExCalibur.Sources.Source
  alias ExCalibur.Sources.SourceWorker

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_source(%Source{} = source) do
    DynamicSupervisor.start_child(__MODULE__, {SourceWorker, source})
  end

  def stop_source(source_id) do
    case Registry.lookup(ExCalibur.SourceRegistry, source_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> :ok
    end
  end

  def start_all_active do
    import Ecto.Query

    sources = ExCalibur.Repo.all(from(s in Source, where: s.status == "active"))
    Enum.each(sources, &start_source/1)
  end
end
