defmodule ExCortex.Senses.Worker do
  @moduledoc false
  use GenServer, restart: :transient

  alias ExCortex.Evaluator
  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Debouncer
  alias ExCortex.Ruminations.Runner
  alias ExCortex.Sandbox
  alias ExCortex.Senses.Reflex
  alias ExCortex.Senses.Sense

  require Logger

  def start_link(%Sense{} = source) do
    GenServer.start_link(__MODULE__, source, name: via(source.id))
  end

  defp via(id), do: {:via, Registry, {ExCortex.SourceRegistry, id}}

  @impl true
  def init(%Sense{} = source) do
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
    case Registry.lookup(ExCortex.SourceRegistry, source_id) do
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
        maybe_write_to_memory(items, state.source)
        steps = Ruminations.list_synapses_for_source(to_string(state.source.id))
        ruminations = Ruminations.list_ruminations_for_source(to_string(state.source.id))
        evaluate_items(items, state.source, steps)
        enqueue_ruminations(items, state.source, ruminations)
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
      Debouncer.enqueue(step, label, items)
    end)
  end

  # No steps: fall back to per-item evaluator (sandbox supported)
  defp evaluate_items(items, source, []) do
    Enum.each(items, fn item ->
      Task.Supervisor.start_child(ExCortex.SourceTaskSupervisor, fn ->
        try do
          content = maybe_run_sandbox(item.content, source)
          Evaluator.evaluate(content)
        rescue
          e -> Logger.error("Source evaluation failed: #{Exception.message(e)}")
        end
      end)
    end)
  end

  defp enqueue_ruminations(_items, _source, []), do: :ok

  defp enqueue_ruminations(items, source, ruminations) do
    label = source.config["label"] || source.source_type
    batch? = source.config["batch_mode"] == true

    Logger.info(
      "[SourceWorker] Firing #{length(items)} item(s) from '#{label}' " <>
        "for #{length(ruminations)} rumination(s)#{if batch?, do: " (batch mode)"}"
    )

    Enum.each(ruminations, fn rumination ->
      if batch? do
        batched_input = batch_items(items)

        Task.Supervisor.start_child(ExCortex.SourceTaskSupervisor, fn ->
          try do
            Runner.run(rumination, batched_input)
          rescue
            e -> Logger.error("[SourceWorker] Rumination #{rumination.name} failed: #{Exception.message(e)}")
          end
        end)
      else
        Enum.each(items, fn item ->
          Task.Supervisor.start_child(ExCortex.SourceTaskSupervisor, fn ->
            try do
              Runner.run(rumination, item.content)
            rescue
              e -> Logger.error("[SourceWorker] Rumination #{rumination.name} failed: #{Exception.message(e)}")
            end
          end)
        end)
      end
    end)
  end

  defp batch_items(items) do
    header = "## Batch: #{length(items)} items\n\n"

    body =
      items
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n---\n\n", fn {item, idx} ->
        "### Item #{idx}\n#{item.content}"
      end)

    header <> body
  end

  # If the source has "write_to_memory: true" in config, write each item directly
  # to memory without any LLM involvement. Useful for price tickers and other
  # structured data that doesn't need synthesis.
  defp maybe_write_to_memory(items, source) do
    if source.config["write_to_memory"] do
      tags = source.config["engram_tags"] || []

      title_template =
        source.config["engram_title"] || source.config["label"] || source.source_type

      Enum.each(items, fn item ->
        now = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M")
        title = String.replace(title_template, "{datetime}", now)

        ExCortex.Memory.create_engram(%{
          title: title,
          body: item.content,
          tags: tags,
          source: "source"
        })
      end)
    end
  end

  defp maybe_run_sandbox(content, source) do
    with reflex_id when reflex_id != nil <- source.reflex_id,
         %Reflex{sandbox: sandbox} when sandbox != nil <- Reflex.get(reflex_id),
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

  defp source_module("git"), do: ExCortex.Senses.GitWatcher
  defp source_module("directory"), do: ExCortex.Senses.DirectoryWatcher
  defp source_module("feed"), do: ExCortex.Senses.FeedWatcher
  defp source_module("url"), do: ExCortex.Senses.UrlWatcher
  defp source_module("websocket"), do: ExCortex.Senses.WebSocketSource
  defp source_module("cortex"), do: ExCortex.Senses.SignalWatcher
  defp source_module("obsidian"), do: ExCortex.Senses.ObsidianWatcher
  defp source_module("email"), do: ExCortex.Senses.EmailSense
  defp source_module("media"), do: ExCortex.Senses.MediaSense
  defp source_module("github_issues"), do: ExCortex.Senses.GithubIssueWatcher
  defp source_module("nextcloud"), do: ExCortex.Senses.NextcloudWatcher

  defp get_interval(config), do: config["interval"] || 60_000

  defp update_source_state(source, new_state) do
    case source
         |> Sense.changeset(%{state: new_state, last_run_at: DateTime.utc_now(), status: "active", error_message: nil})
         |> ExCortex.Repo.update() do
      {:ok, updated} -> updated
      {:error, _} -> source
    end
  end

  defp mark_source_error(source, reason) do
    source
    |> Sense.changeset(%{status: "error", error_message: inspect(reason)})
    |> ExCortex.Repo.update()
  end
end
