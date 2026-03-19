defmodule ExCortex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias ExCortex.Ruminations.Daydream
  alias ExCortex.Senses.Supervisor, as: SensesSupervisor

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

    # Auto-migrate on boot (safe for releases — no-ops if already up)
    ExCortex.Release.migrate()

    sandbox? = Application.get_env(:ex_cortex, :sql_sandbox, false)
    mode = if sandbox?, do: :server, else: ExCortex.BootMode.current()
    children = children_for_mode(mode, sandbox?)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExCortex.Supervisor]
    result = Supervisor.start_link(children, opts)

    if mode in [:server, :full], do: OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:ex_cortex, :repo])
    ExCortex.Settings.apply_to_runtime()
    check_cli_tools()
    write_pid_file()
    check_restart_status()
    result
  end

  defp children_for_mode(mode, sandbox?) do
    base = base_children()
    senses = senses_children()
    scheduled = if sandbox?, do: [], else: scheduled_children()
    web = [ExCortexWeb.Endpoint]
    tui = [ExCortexTUI.App]
    hud = [ExCortexTUI.HUD]

    case mode do
      :server -> base ++ scheduled ++ senses ++ web
      :tui -> base ++ scheduled ++ senses ++ tui
      :hud -> base ++ hud
      :full -> base ++ scheduled ++ senses ++ web ++ tui
    end
  end

  defp base_children do
    [
      ExCortexWeb.Telemetry,
      ExCortex.Repo,
      ExCortex.Core.Registry,
      {Oban, Application.fetch_env!(:ex_cortex, Oban)},
      {DNSCluster, query: Application.get_env(:ex_cortex, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ExCortex.PubSub},
      {Registry, keys: :unique, name: ExCortex.SourceRegistry},
      {Task.Supervisor, name: ExCortex.SourceTaskSupervisor, max_children: 10},
      {Task.Supervisor, name: ExCortex.AsyncTaskSupervisor},
      ExCortex.AppTelemetry,
      ExCortex.Ruminations.Debouncer
    ]
  end

  defp senses_children do
    [
      SensesSupervisor,
      {Task, fn -> SensesSupervisor.start_all_active() end}
    ]
  end

  defp scheduled_children do
    [
      ExCortex.Ruminations.Scheduler,
      ExCortex.Memory.EngramTriggerRunner,
      ExCortex.Signals.TriggerRunner,
      ExCortex.Senses.Feedback
    ]
  end

  defp check_restart_status do
    import Ecto.Query

    try do
      running_runs =
        ExCortex.Repo.all(from(qr in Daydream, where: qr.status == "running"))

      if running_runs != [] do
        Logger.info("[Boot] Found #{length(running_runs)} interrupted daydream(s) — marking interrupted")

        ExCortex.Repo.update_all(
          from(qr in Daydream, where: qr.status == "running"),
          set: [status: "interrupted"]
        )
      end
    rescue
      e -> Logger.warning("[Boot] Could not check restart status: #{Exception.message(e)}")
    end
  end

  defp write_pid_file do
    pid = System.pid()
    path = Path.join(File.cwd!(), ".ex_cortex.pid")
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
    ExCortexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
