defmodule ExCalibur.Media do
  @moduledoc "Shared helpers for media tool operations."

  def media_dir, do: ExCalibur.Settings.get(:media_dir) || "/tmp/ex_calibur/media"

  def job_dir do
    dir = Path.join(media_dir(), Ecto.UUID.generate())
    File.mkdir_p!(dir)
    dir
  end

  def cleanup(dir), do: File.rm_rf(dir)
end
