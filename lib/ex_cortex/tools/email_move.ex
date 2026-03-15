defmodule ExCortex.Tools.EmailMove do
  @moduledoc "Tool: move email threads to Maildir folders and update notmuch tags."

  require Logger

  @mail_root "#{System.get_env("HOME")}/mail/zoho"

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "email_move",
      description:
        "Move an email thread to a Maildir folder. Creates the folder if it doesn't exist. " <>
          "Also applies the matching notmuch tag and removes the inbox tag. " <>
          "Example: thread_id='0000000000000042', folder='Newsletter'",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "thread_id" => %{"type" => "string", "description" => "The notmuch thread ID"},
          "folder" => %{
            "type" => "string",
            "description" =>
              "Target folder name (e.g. 'Newsletter', 'Spam', 'Personal', 'Transactional', 'Jobs')"
          }
        },
        "required" => ["thread_id", "folder"]
      },
      callback: &call/1
    )
  end

  def call(%{"thread_id" => thread_id, "folder" => folder}) do
    mail_root = mail_root()
    tag = folder |> String.downcase() |> String.replace(~r/[^a-z0-9-]/, "-")

    with :ok <- ensure_maildir(mail_root, folder),
         {:ok, files} <- find_thread_files(thread_id),
         :ok <- move_files(files, mail_root, folder),
         :ok <- retag(thread_id, tag) do
      {:ok, "Moved #{length(files)} message(s) to #{folder}/, tagged +#{tag} -inbox"}
    end
  end

  defp mail_root do
    # notmuch's database.mail_root is the top-level mail dir (e.g. ~/mail)
    # but Maildir folders live inside the account subdir (e.g. ~/mail/zoho/)
    # Use the first subdirectory that contains an Inbox as the actual root
    case System.cmd("notmuch", ["config", "get", "database.mail_root"], stderr_to_stdout: true) do
      {path, 0} ->
        base = String.trim(path)
        find_account_root(base)

      _ ->
        @mail_root
    end
  rescue
    _ -> @mail_root
  end

  defp find_account_root(base) do
    case File.ls(base) do
      {:ok, entries} ->
        account =
          Enum.find(entries, fn entry ->
            Path.join([base, entry, "Inbox"]) |> File.dir?()
          end)

        if account, do: Path.join(base, account), else: base

      _ ->
        base
    end
  end

  defp ensure_maildir(mail_root, folder) do
    base = Path.join(mail_root, folder)

    for sub <- ["cur", "new", "tmp"] do
      File.mkdir_p!(Path.join(base, sub))
    end

    :ok
  rescue
    e -> {:error, "Failed to create Maildir #{folder}: #{Exception.message(e)}"}
  end

  defp find_thread_files(thread_id) do
    args = ["search", "--output=files", "--format=text", "thread:#{thread_id}"]

    case System.cmd("notmuch", args, stderr_to_stdout: true) do
      {output, 0} ->
        files = output |> String.trim() |> String.split("\n", trim: true)
        {:ok, files}

      {output, code} ->
        {:error, "notmuch search --output=files failed (exit #{code}): #{String.trim(output)}"}
    end
  rescue
    e -> {:error, "notmuch not available: #{Exception.message(e)}"}
  end

  defp move_files([], _mail_root, folder) do
    {:error, "No files found for thread — cannot move to #{folder}"}
  end

  defp move_files(files, mail_root, folder) do
    dest_cur = Path.join([mail_root, folder, "cur"])

    Enum.each(files, fn src ->
      filename = Path.basename(src)
      dest = Path.join(dest_cur, filename)

      if src != dest do
        File.rename!(src, dest)
        Logger.debug("[EmailMove] #{filename} → #{folder}/cur/")
      end
    end)

    # Re-index so notmuch knows files moved
    System.cmd("notmuch", ["new", "--quiet"], stderr_to_stdout: true)
    :ok
  rescue
    e -> {:error, "Failed to move files: #{Exception.message(e)}"}
  end

  defp retag(thread_id, tag) do
    args = ["tag", "+#{tag}", "-inbox", "--", "thread:#{thread_id}"]

    case System.cmd("notmuch", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, code} -> {:error, "notmuch tag failed (exit #{code}): #{String.trim(output)}"}
    end
  rescue
    e -> {:error, "notmuch not available: #{Exception.message(e)}"}
  end
end
