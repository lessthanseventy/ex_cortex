defmodule Mix.Tasks.Email.Archive do
  @moduledoc """
  Archive emails from a given year into an Archive_YYYY Maildir folder.

  Finds all emails tagged `archive` (or still in inbox) for the given year,
  moves them to `<mail_root>/Archive_YYYY/cur/`, strips UIDs from filenames,
  and tags them `+archive -inbox`.

  ## Usage

      # Archive all of 2025
      mix email.archive 2025

      # Archive previous year (default: last year)
      mix email.archive
  """

  use Mix.Task

  require Logger

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    year =
      case args do
        [y | _] -> String.to_integer(y)
        [] -> Date.utc_today().year - 1
      end

    folder = "Archive_#{year}"
    dest_cur = Path.join([mail_root(), folder, "cur"])

    # Create Maildir structure
    for sub <- ["cur", "new", "tmp"] do
      File.mkdir_p!(Path.join([mail_root(), folder, sub]))
    end

    # Tag any inbox emails from this year as archive
    {_, 0} =
      System.cmd("notmuch", ["tag", "+archive", "-inbox", "--", "tag:inbox AND date:#{year}-01-01..#{year}-12-31"],
        stderr_to_stdout: true
      )

    # Find all files for archived emails in this year
    {output, 0} =
      System.cmd(
        "notmuch",
        ["search", "--output=files", "--format=text", "tag:archive AND date:#{year}-01-01..#{year}-12-31"],
        stderr_to_stdout: true
      )

    files =
      output
      |> String.split("\n", trim: true)
      |> Enum.filter(&File.exists?/1)
      # Skip files already in the target folder
      |> Enum.reject(&String.contains?(&1, "/#{folder}/"))

    if files == [] do
      Mix.shell().info("No emails to archive for #{year}.")
    else
      count = Enum.reduce(files, 0, fn src, acc -> archive_file_to(src, dest_cur, acc) end)

      # Reindex notmuch
      System.cmd("notmuch", ["new", "--quiet"], stderr_to_stdout: true)

      Mix.shell().info("Archived #{count} files → #{folder}/")
    end
  end

  defp archive_file_to(src, dest_cur, acc) do
    filename = Path.basename(src)
    clean = Regex.replace(~r/,U=\d+/, filename, "")
    dest = Path.join(dest_cur, clean)

    if src == dest do
      acc
    else
      File.rename!(src, dest)
      acc + 1
    end
  end

  defp mail_root do
    base = ExCortex.Settings.resolve(:mail_root, env_var: "MAIL_ROOT", default: Path.expand("~/mail"))
    ExCortex.Tools.EmailMove.find_account_root(base)
  end
end
