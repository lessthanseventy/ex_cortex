defmodule ExCortex.Senses.Supervisor do
  @moduledoc false
  use DynamicSupervisor

  alias ExCortex.Senses.Sense
  alias ExCortex.Senses.Worker

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_source(%Sense{} = source) do
    DynamicSupervisor.start_child(__MODULE__, {Worker, source})
  end

  def stop_source(source_id) do
    case Registry.lookup(ExCortex.SourceRegistry, source_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> :ok
    end
  end

  def start_all_active do
    import Ecto.Query

    sources = ExCortex.Repo.all(from(s in Sense, where: s.status == "active"))
    Enum.each(sources, &start_source/1)
  end
end
