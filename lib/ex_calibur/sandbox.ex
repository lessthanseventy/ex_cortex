defmodule ExCalibur.Sandbox do
  @moduledoc false
  require Logger

  @default_timeout 120_000

  def run(sandbox_config, working_dir) do
    case Map.get(sandbox_config, :mode, :host) do
      :host -> run_host(sandbox_config, working_dir)
      :container -> run_container(sandbox_config, working_dir)
    end
  end

  def wrap_content(source_content, tool_output, cmd) do
    """
    ## Source Content
    #{source_content}

    ## Tool Output (#{cmd})
    #{tool_output}
    """
  end

  defp run_host(config, working_dir) do
    cmd = Map.fetch!(config, :cmd)
    timeout = Map.get(config, :timeout, @default_timeout)

    [command | args] = OptionParser.split(cmd)

    task =
      Task.async(fn ->
        System.cmd(command, args, cd: working_dir, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {output, exit_code}} ->
        {:ok, output, exit_code}

      nil ->
        {:error, :timeout}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp run_container(config, working_dir) do
    image = Map.fetch!(config, :image)
    cmd = Map.fetch!(config, :cmd)
    timeout = Map.get(config, :timeout, @default_timeout)
    setup = Map.get(config, :setup)

    full_cmd =
      if setup do
        "#{setup} && #{cmd}"
      else
        cmd
      end

    args =
      [
        "run",
        "--rm",
        "-v",
        "#{working_dir}:/app:Z",
        "-w",
        "/app",
        image,
        "sh",
        "-c",
        full_cmd
      ]

    task =
      Task.async(fn ->
        System.cmd("podman", args, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {output, exit_code}} ->
        {:ok, output, exit_code}

      nil ->
        {:error, :timeout}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
