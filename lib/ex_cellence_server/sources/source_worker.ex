defmodule ExCellenceServer.Sources.SourceWorker do
  @moduledoc false
  use GenServer, restart: :transient

  alias ExCellenceServer.Evaluator
  alias ExCellenceServer.Sources.Source

  require Logger

  def start_link(%Source{} = source) do
    GenServer.start_link(__MODULE__, source, name: via(source.id))
  end

  defp via(id), do: {:via, Registry, {ExCellenceServer.SourceRegistry, id}}

  @impl true
  def init(%Source{} = source) do
    mod = source_module(source.source_type)

    case mod.init(source.config) do
      {:ok, worker_state} ->
        interval = get_interval(source.config)
        timer = Process.send_after(self(), :fetch, interval)
        {:ok, %{source: source, mod: mod, worker_state: worker_state, timer: timer, interval: interval}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:fetch, state) do
    case state.mod.fetch(state.worker_state, state.source.config) do
      {:ok, items, new_worker_state} ->
        Enum.each(items, &evaluate_item/1)
        update_source_state(state.source, new_worker_state)
        timer = Process.send_after(self(), :fetch, state.interval)
        {:noreply, %{state | worker_state: new_worker_state, timer: timer}}

      {:error, reason} ->
        mark_source_error(state.source, reason)
        {:stop, :fetch_error, state}
    end
  end

  defp evaluate_item(item) do
    Task.Supervisor.start_child(ExCellenceServer.SourceTaskSupervisor, fn ->
      try do
        Evaluator.evaluate(item.guild_name, item.content)
      rescue
        e -> Logger.error("Source evaluation failed: #{Exception.message(e)}")
      end
    end)
  end

  defp source_module("git"), do: ExCellenceServer.Sources.GitWatcher
  defp source_module("directory"), do: ExCellenceServer.Sources.DirectoryWatcher
  defp source_module("feed"), do: ExCellenceServer.Sources.FeedWatcher
  defp source_module("url"), do: ExCellenceServer.Sources.UrlWatcher
  defp source_module("websocket"), do: ExCellenceServer.Sources.WebSocketSource

  defp get_interval(config), do: config["interval"] || 60_000

  defp update_source_state(source, new_state) do
    source
    |> Source.changeset(%{state: new_state, last_run_at: DateTime.utc_now(), status: "active", error_message: nil})
    |> ExCellenceServer.Repo.update()
  end

  defp mark_source_error(source, reason) do
    source
    |> Source.changeset(%{status: "error", error_message: inspect(reason)})
    |> ExCellenceServer.Repo.update()
  end
end
