defmodule ExCalibur.Tools.WriteNextcloud do
  @moduledoc false

  alias ExCalibur.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "write_nextcloud",
      description: "Write or create a file in Nextcloud. Creates parent directories automatically.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Full file path in Nextcloud, e.g. '/ExCalibur/reports/summary.md'"
          },
          "content" => %{"type" => "string", "description" => "File content to write"}
        },
        "required" => ["path", "content"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path, "content" => content}) do
    path |> Path.dirname() |> ensure_dirs()

    case Client.put_file(path, content) do
      :ok -> {:ok, "Wrote #{byte_size(content)} bytes to #{path}"}
      {:error, reason} -> {:error, "Failed to write #{path}: #{inspect(reason)}"}
    end
  end

  defp ensure_dirs("/"), do: :ok

  defp ensure_dirs(path) do
    parts = path |> String.split("/", trim: true)

    Enum.reduce(parts, "", fn part, acc ->
      dir = "#{acc}/#{part}"
      Client.mkcol(dir)
      dir
    end)
  end
end
