defmodule ExCalibur.Sources.SourceWorker do
  @moduledoc false
  use GenServer, restart: :transient

  alias ExCalibur.Evaluator
  alias ExCalibur.QuestDebouncer
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
        # Restore persisted state (e.g. seen_ids) so workers don't re-fire on restart
        saved = for {k, v} <- source.state || %{}, into: %{}, do: {String.to_atom(k), v}
        worker_state = Map.merge(worker_state, saved)
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
    timer = Process.send_after(self(), :fetch, 0)
    {:noreply, %{state | timer: timer}}
  end

  @impl true
  def handle_info(:fetch, state) do
    case state.mod.fetch(state.worker_state, state.source.config) do
      {:ok, [], new_worker_state} ->
        source = update_source_state(state.source, new_worker_state)
        timer = Process.send_after(self(), :fetch, state.interval)
        {:noreply, %{state | source: source, worker_state: new_worker_state, timer: timer}}

      {:ok, items, new_worker_state} ->
        maybe_write_to_lore(items, state.source)
        steps = Quests.list_steps_for_source(to_string(state.source.id))
        quests = Quests.list_quests_for_source(to_string(state.source.id))
        evaluate_items(items, state.source, steps)
        enqueue_quests(items, state.source, quests)
        source = update_source_state(state.source, new_worker_state)
        timer = Process.send_after(self(), :fetch, state.interval)
        {:noreply, %{state | source: source, worker_state: new_worker_state, timer: timer}}

      {:error, reason} ->
        mark_source_error(state.source, reason)
        {:stop, :fetch_error, state}
    end
  end

  # Step-linked sources: enqueue items into the debouncer, which coalesces
  # all sources that fire in the same window into a single step run.
  defp evaluate_items(items, source, [_ | _] = steps) do
    label = source.config["label"] || source.source_type
    Logger.info("[SourceWorker] Enqueuing #{length(items)} items from '#{label}' for #{length(steps)} step(s)")

    Enum.each(steps, fn step ->
      QuestDebouncer.enqueue(step, label, items)
    end)
  end

  # No steps: fall back to per-item evaluator (sandbox supported)
  defp evaluate_items(items, source, []) do
    Enum.each(items, fn item ->
      Task.Supervisor.start_child(ExCalibur.SourceTaskSupervisor, fn ->
        try do
          content = maybe_run_sandbox(item.content, source)
          Evaluator.evaluate(content)
        rescue
          e -> Logger.error("Source evaluation failed: #{Exception.message(e)}")
        end
      end)
    end)
  end

  defp enqueue_quests(_items, _source, []), do: :ok

  defp enqueue_quests(items, source, quests) do
    label = source.config["label"] || source.source_type
    Logger.info("[SourceWorker] Firing #{length(items)} item(s) from '#{label}' for #{length(quests)} quest(s)")

    Enum.each(quests, fn quest ->
      Enum.each(items, fn item ->
        Task.Supervisor.start_child(ExCalibur.SourceTaskSupervisor, fn ->
          try do
            QuestRunner.run(quest, item.content)
          rescue
            e -> Logger.error("[SourceWorker] Quest #{quest.name} failed: #{Exception.message(e)}")
          end
        end)
      end)
    end)
  end

  # If the source has "write_to_lore: true" in config, write each item directly
  # to lore without any LLM involvement. Useful for price tickers and other
  # structured data that doesn't need synthesis.
  defp maybe_write_to_lore(items, source) do
    if source.config["write_to_lore"] do
      tags = source.config["lore_tags"] || []
      title_template = source.config["lore_title"] || source.config["label"] || source.source_type

      Enum.each(items, fn item ->
        now = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M")
        title = String.replace(title_template, "{datetime}", now)

        ExCalibur.Lore.create_entry(%{
          title: title,
          body: item.content,
          tags: tags,
          source: "source"
        })
      end)
    end
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
  defp source_module("lodge"), do: ExCalibur.Sources.LodgeWatcher
  defp source_module("obsidian"), do: ExCalibur.Sources.ObsidianWatcher
  defp source_module("email"), do: ExCalibur.Sources.EmailSource
  defp source_module("media"), do: ExCalibur.Sources.MediaSource
  defp source_module("github_issues"), do: ExCalibur.Sources.GithubIssueWatcher
  defp source_module("nextcloud"), do: ExCalibur.Sources.NextcloudWatcher

  defp get_interval(config), do: config["interval"] || 60_000

  defp update_source_state(source, new_state) do
    case source
         |> Source.changeset(%{state: new_state, last_run_at: DateTime.utc_now(), status: "active", error_message: nil})
         |> ExCalibur.Repo.update() do
      {:ok, updated} -> updated
      {:error, _} -> source
    end
  end

  defp mark_source_error(source, reason) do
    source
    |> Source.changeset(%{status: "error", error_message: inspect(reason)})
    |> ExCalibur.Repo.update()
  end
end
