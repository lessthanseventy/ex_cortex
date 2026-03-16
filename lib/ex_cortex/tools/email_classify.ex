defmodule ExCortex.Tools.EmailClassify do
  @moduledoc "Tool: classify an email thread into a category. Tags and moves to the matching Maildir folder."

  require Logger

  @categories %{
    "newsletter" => "Newsletter",
    "promotion" => "Promotion",
    "spam" => "Spam",
    "personal" => "Personal",
    "transactional" => "Transactional",
    "receipt" => "Receipt",
    "jobs" => "Jobs",
    "job_alert" => "Job_Alert",
    "notification" => "Notification",
    "social" => "Social",
    "github" => "GitHub",
    "appsignal" => "AppSignal",
    "technical" => "Technical"
  }

  @category_names Map.keys(@categories)

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "email_classify",
      description:
        "Classify an email thread into a category. " <>
          "This tags the thread and moves it to the matching Maildir folder. " <>
          "Use the Thread-ID from the email header as thread_id.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "thread_id" => %{
            "type" => "string",
            "description" => "The notmuch thread ID from the Thread-ID field"
          },
          "category" => %{
            "type" => "string",
            "enum" => @category_names,
            "description" =>
              "newsletter (marketing, digests), promotion (sales, deals, coupons), spam (junk), " <>
                "personal (real people), transactional (confirmations, password resets), " <>
                "receipt (purchase receipts, invoices), jobs (applications, recruiters), " <>
                "job_alert (job board notifications), notification (automated alerts), " <>
                "social (LinkedIn, Twitter), github (PRs, issues, CI), " <>
                "appsignal (incidents), technical (server alerts, DevOps)"
          }
        },
        "required" => ["thread_id", "category"]
      },
      callback: &call/1
    )
  end

  def call(%{"thread_id" => thread_id, "category" => category}) do
    category = String.downcase(category)

    case Map.fetch(@categories, category) do
      {:ok, folder} ->
        with :ok <- tag(thread_id, category),
             {:ok, move_msg} <- ExCortex.Tools.EmailMove.call(%{"thread_id" => thread_id, "folder" => folder}) do
          {:ok, "Classified as #{category} → #{folder}/. #{move_msg}"}
        end

      :error ->
        {:error, "Unknown category '#{category}'. Use one of: #{Enum.join(@category_names, ", ")}"}
    end
  end

  defp tag(thread_id, category) do
    args = ["tag", "+#{category}", "-inbox", "--", "thread:#{thread_id}"]

    case System.cmd("notmuch", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, code} -> {:error, "notmuch tag failed (exit #{code}): #{String.trim(output)}"}
    end
  rescue
    e -> {:error, "notmuch not available: #{Exception.message(e)}"}
  end
end
