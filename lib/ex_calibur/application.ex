defmodule ExCalibur.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias ExCalibur.Quests.QuestRun
  alias ExCalibur.Sources.SourceSupervisor

  require Logger

  @cli_tools ~w(
    obsidian-cli notmuch msmtp yt-dlp ffmpeg tesseract
    ddgr w3m pandoc pdftotext jq gh git podman
  )

  @impl true
  def start(_type, _args) do
    # SaladUI requires TwMerge.Cache ETS table
    if :ets.whereis(:tw_merge_cache) == :undefined do
      TwMerge.Cache.create_table()
      TwMerge.Cache.insert(:class_tree, TwMerge.ClassTree.generate())
    end

    children = [
      ExCaliburWeb.Telemetry,
      ExCalibur.Repo,
      {Oban, Application.fetch_env!(:ex_cellence, Oban)},
      {DNSCluster, query: Application.get_env(:ex_calibur, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ExCalibur.PubSub},
      {Registry, keys: :unique, name: ExCalibur.SourceRegistry},
      {Task.Supervisor, name: ExCalibur.SourceTaskSupervisor, max_children: 4},
      {Task.Supervisor, name: ExCalibur.AsyncTaskSupervisor},
      ExCalibur.QuestDebouncer,
      SourceSupervisor,
      {Task, fn -> SourceSupervisor.start_all_active() end},
      ExCalibur.PubSubBridge,
      ExCalibur.ScheduledQuestRunner,
      ExCalibur.LoreTriggerRunner,
      ExCalibur.LodgeTriggerRunner,
      ExCaliburWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExCalibur.Supervisor]
    result = Supervisor.start_link(children, opts)
    check_cli_tools()
    write_pid_file()
    check_restart_status()
    result
  end

  defp check_restart_status do
    import Ecto.Query

    try do
      running_runs =
        ExCalibur.Repo.all(from(qr in QuestRun, where: qr.status == "running"))

      if running_runs != [] do
        Logger.info("[Boot] Found #{length(running_runs)} interrupted quest run(s) — marking complete")

        Enum.each(running_runs, fn run ->
          ExCalibur.Repo.update_all(
            from(qr in QuestRun, where: qr.id == ^run.id),
            set: [status: "complete"]
          )
        end)
      end
    rescue
      e -> Logger.warning("[Boot] Could not check restart status: #{Exception.message(e)}")
    end
  end

  defp write_pid_file do
    pid = System.pid()
    path = Path.join(File.cwd!(), ".ex_calibur.pid")
    File.write!(path, pid)
    Logger.info("PID file written: #{path} (#{pid})")
  end

  defp check_cli_tools do
    {found, missing} =
      Enum.split_with(@cli_tools, &System.find_executable/1)

    if missing != [] do
      Logger.warning("CLI tools not found: #{Enum.join(missing, ", ")} — related tools/sources may fail")
    end

    Logger.info("CLI tools available: #{Enum.join(found, ", ")}")
    :persistent_term.put(:cli_tool_status, %{available: found, missing: missing})
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ExCaliburWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
