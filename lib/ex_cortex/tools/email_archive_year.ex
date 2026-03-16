defmodule ExCortex.Tools.EmailArchiveYear do
  @moduledoc "Tool: archive all inbox emails from a given year into ZZZ_Archive_YYYY Maildir folder."

  require Logger

  @mail_root Path.expand("~/mail/zoho")

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "email_archive_year",
      description:
        "Archive all inbox emails from a given year. Moves them to ZZZ_Archive_YYYY/ " <>
          "Maildir folder and tags +archive -inbox. Call with the year to archive.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "year" => %{
            "type" => "integer",
            "description" => "The year to archive, e.g. 2025"
          }
        },
        "required" => ["year"]
      },
      callback: &call/1
    )
  end

  def call(%{"year" => year}) when is_integer(year) do
    folder = "ZZZ_Archive_#{year}"
    dest_cur = Path.join([@mail_root, folder, "cur"])

    for sub <- ["cur", "new", "tmp"] do
      File.mkdir_p!(Path.join([@mail_root, folder, sub]))
    end

    # Tag inbox emails from this year as archive
    System.cmd(
      "notmuch",
      ["tag", "+archive", "-inbox", "--", "tag:inbox AND date:#{year}-01-01..#{year}-12-31"],
      stderr_to_stdout: true
    )

    # Find files to move
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
      |> Enum.reject(&String.contains?(&1, "/#{folder}/"))

    if files == [] do
      {:ok, "No emails to archive for #{year}."}
    else
      count =
        Enum.reduce(files, 0, fn src, acc ->
          filename = Path.basename(src)
          clean = Regex.replace(~r/,U=\d+/, filename, "")
          dest = Path.join(dest_cur, clean)

          if src != dest and not File.exists?(dest) do
            File.rename!(src, dest)
            acc + 1
          else
            acc
          end
        end)

      Logger.info("[EmailArchiveYear] Archived #{count} files → #{folder}/")
      System.cmd("notmuch", ["new", "--quiet"], stderr_to_stdout: true)
      {:ok, "Archived #{count} emails → #{folder}/"}
    end
  rescue
    e -> {:error, "Archive failed: #{Exception.message(e)}"}
  end

  def call(%{"year" => year}) when is_binary(year) do
    call(%{"year" => String.to_integer(year)})
  end
end
