alias ExCortex.Ruminations
alias ExCortex.Repo
alias ExCortex.Senses.Sense
import Ecto.Query

sense = Repo.one!(from s in Sense, where: s.source_type == "email")

# Pause the 5-step pipeline so only the bulk cleaner runs
pipeline = Repo.one(from r in ExCortex.Ruminations.Rumination, where: r.name == "Email Management Pipeline")
if pipeline && pipeline.status == "active" do
  Ruminations.update_rumination(pipeline, %{status: "paused"})
  IO.puts("Paused Email Management Pipeline")
end

# Check if already exists
if Repo.one(from r in ExCortex.Ruminations.Rumination, where: r.name == "Email Backlog Cleanup") do
  IO.puts("Email Backlog Cleanup already exists — skipping")
else
  {:ok, step} = Ruminations.create_synapse(%{
    name: "Bulk: Classify & File",
    description: """
    You receive a batch of emails. For EACH email in the batch, decide its category
    and call email_move to file it into the correct Maildir folder.

    Categories (use these exact folder names):
    - Newsletter — marketing emails, digests, mailing lists
    - Spam — junk, scams, unsolicited
    - Personal — from real people you know
    - Transactional — receipts, confirmations, password resets, account notifications
    - Jobs — job applications, recruiter emails, interview scheduling
    - Notifications — automated alerts from services (GitHub, Slack, etc.)
    - Social — social media notifications (LinkedIn, Twitter, etc.)

    For each email, call email_move with the thread_id and folder name.
    Process ALL emails in the batch. Do not stop early or ask for clarification.
    If unsure, use "Notifications" as the default.
    """,
    trigger: "manual",
    output_type: "freeform",
    cluster_name: "Triage",
    loop_tools: ["email_move", "email_tag"],
    max_tool_iterations: 60,
    dangerous_tool_mode: "execute",
    roster: [%{"who" => "journeyman", "how" => "solo", "when" => "sequential"}]
  })

  {:ok, rum} = Ruminations.create_rumination(%{
    name: "Email Backlog Cleanup",
    description: "One-step bulk classifier. Moves each email to the appropriate Maildir folder.",
    trigger: "source",
    source_ids: [to_string(sense.id)],
    status: "active",
    steps: [%{"step_id" => step.id, "order" => 1}]
  })

  IO.puts("Created: #{rum.name} (id: #{rum.id}), synapse #{step.id}")
  IO.puts("Wired to sense: #{sense.id}")
end
