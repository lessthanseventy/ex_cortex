defmodule ExCalibur.Sources.SourceWorker do
  @moduledoc false
  use GenServer, restart: :transient

  alias ExCalibur.Evaluator
  alias ExCalibur.QuestRunner
  alias ExCalibur.Quests
  alias ExCalibur.Sandbox
  alias ExCalibur.Sources.Book
  alias ExCalibur.Sources.Source

  require Logger

  def start_link(%Source{} = source) do
    GenServer.start_link(__MODULE__, source, name: via(source.id))
  end

  defp via(id), do: {:via, Registry, {ExCalibur.SourceRegistry, id}}

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

  def sync(source_id) do
    case Registry.lookup(ExCalibur.SourceRegistry, source_id) do
      [{pid, _}] -> send(pid, :sync_now)
      [] -> :ok
    end
  end

  @impl true
  def handle_info(:sync_now, state) do
    Process.cancel_timer(state.timer)
    jitter = :rand.uniform(10_000)
    timer = Process.send_after(self(), :fetch, jitter)
    {:noreply, %{state | timer: timer}}
  end

  @impl true
  def handle_info(:fetch, state) do
    case state.mod.fetch(state.worker_state, state.source.config) do
      {:ok, items, new_worker_state} ->
        Enum.each(items, &evaluate_item(&1, state.source))
        update_source_state(state.source, new_worker_state)
        timer = Process.send_after(self(), :fetch, state.interval)
        {:noreply, %{state | worker_state: new_worker_state, timer: timer}}

      {:error, reason} ->
        mark_source_error(state.source, reason)
        {:stop, :fetch_error, state}
    end
  end

  defp evaluate_item(item, source) do
    Task.Supervisor.start_child(ExCalibur.SourceTaskSupervisor, fn ->
      try do
        content = maybe_run_sandbox(item.content, source)
        quests = Quests.list_quests_for_source(to_string(source.id))

        if quests == [] do
          Evaluator.evaluate(content)
        else
          Enum.each(quests, fn quest ->
            Logger.info("[SourceWorker] Running quest #{quest.id} (#{quest.name}) for source #{source.id}")
            QuestRunner.run(quest, content)
          end)
        end
      rescue
        e -> Logger.error("Source evaluation failed: #{Exception.message(e)}")
      end
    end)
  end

  defp maybe_run_sandbox(content, source) do
    with book_id when book_id != nil <- source.book_id,
         %Book{sandbox: sandbox} when sandbox != nil <- Book.get(book_id),
         working_dir when working_dir != nil <- sandbox_working_dir(source) do
      case Sandbox.run(sandbox, working_dir) do
        {:ok, output, _exit_code} ->
          Sandbox.wrap_content(content, output, sandbox.cmd)

        {:error, reason} ->
          Logger.warning("Sandbox execution failed: #{inspect(reason)}")
          content
      end
    else
      _ -> content
    end
  end

  defp sandbox_working_dir(source) do
    case source.source_type do
      "directory" -> source.config["path"]
      "git" -> source.config["repo_path"]
      _ -> nil
    end
  end

  defp source_module("git"), do: ExCalibur.Sources.GitWatcher
  defp source_module("directory"), do: ExCalibur.Sources.DirectoryWatcher
  defp source_module("feed"), do: ExCalibur.Sources.FeedWatcher
  defp source_module("url"), do: ExCalibur.Sources.UrlWatcher
  defp source_module("websocket"), do: ExCalibur.Sources.WebSocketSource

  defp get_interval(config), do: config["interval"] || 60_000

  defp update_source_state(source, new_state) do
    source
    |> Source.changeset(%{state: new_state, last_run_at: DateTime.utc_now(), status: "active", error_message: nil})
    |> ExCalibur.Repo.update()
  end

  defp mark_source_error(source, reason) do
    source
    |> Source.changeset(%{status: "error", error_message: inspect(reason)})
    |> ExCalibur.Repo.update()
  end
end
