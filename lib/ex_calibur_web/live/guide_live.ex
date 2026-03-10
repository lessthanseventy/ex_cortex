defmodule ExCaliburWeb.GuideLive do
  use ExCaliburWeb, :live_view

  @campaign_snippet """
  steps:
    - quest_id: "1"
      order: 1
    - quest_id: "2"
      order: 2
  """

  @branch_snippet """
  steps:
    - type: branch
      order: 1
      quests:
        - "quest_id_accuracy"
        - "quest_id_tone"
      synthesizer: "quest_id_synthesis"
  """

  @challenger_snippet """
  roster:
    - who: all
      how: consensus
    - who: challenger
      how: solo
  """

  @fallback_snippet "config :ex_calibur, :model_fallback_chain, [\"phi4-mini\", \"gemma3:4b\", \"llama3:8b\"]"

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Guide",
       campaign_snippet: @campaign_snippet,
       branch_snippet: @branch_snippet,
       challenger_snippet: @challenger_snippet,
       fallback_snippet: @fallback_snippet
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto py-8 px-4 space-y-10">
      <div>
        <h1 class="text-3xl font-bold mb-1">ExCalibur Guide</h1>
        <p class="text-muted-foreground">
          How to get the most out of quests, campaigns, and guild features.
        </p>
      </div>

      <section>
        <h2 class="text-xl font-semibold mb-3">Campaigns</h2>
        <p class="text-sm text-muted-foreground mb-3">
          Campaigns chain quests together. Each step's output becomes context for the next step.
          Create a campaign in <.link navigate={~p"/quests"} class="underline">Quests</.link>
          and add quest steps in order.
        </p>
        <pre class="bg-muted rounded p-4 text-xs overflow-x-auto">{@campaign_snippet}</pre>
        <p class="text-sm text-muted-foreground mt-2">
          The second quest receives a structured handoff block: the prior verdict, member findings,
          and an open question tailored to its domain.
        </p>
      </section>

      <section>
        <h2 class="text-xl font-semibold mb-3">Branch Steps (Parallel Workstreams)</h2>
        <p class="text-sm text-muted-foreground mb-3">
          Branch steps run multiple quests simultaneously and feed all results to a synthesizer quest.
          Use this for independent checks (accuracy, tone, safety) that run in parallel.
        </p>
        <pre class="bg-muted rounded p-4 text-xs overflow-x-auto">{@branch_snippet}</pre>
      </section>

      <section>
        <h2 class="text-xl font-semibold mb-3">The Challenger Member</h2>
        <p class="text-sm text-muted-foreground mb-3">
          Add <code class="bg-muted px-1 rounded">who: "challenger"</code> to any roster step to insert
          a skeptic that demands evidence before accepting a pass verdict. Defaults to NEEDS WORK.
        </p>
        <pre class="bg-muted rounded p-4 text-xs overflow-x-auto">{@challenger_snippet}</pre>
      </section>

      <section>
        <h2 class="text-xl font-semibold mb-3">Rank-Gated Quests</h2>
        <p class="text-sm text-muted-foreground mb-3">
          Set <code class="bg-muted px-1 rounded">min_rank</code> on a quest to prevent it from running
          unless at least one active member meets that rank. Options:
          <code class="bg-muted px-1 rounded">apprentice</code>,
          <code class="bg-muted px-1 rounded">journeyman</code>,
          <code class="bg-muted px-1 rounded">master</code>.
        </p>
        <p class="text-sm text-muted-foreground">
          Returns <code class="bg-muted px-1 rounded">error: rank_insufficient</code>
          if no eligible members exist.
        </p>
      </section>

      <section>
        <h2 class="text-xl font-semibold mb-3">Guild Charter Documents</h2>
        <p class="text-sm text-muted-foreground mb-3">
          Each guild can have a charter — shared values, domain rules, output format expectations —
          that gets prepended to every member's context during evaluation.
          Edit charters in <.link navigate={~p"/guild-hall"} class="underline">Guild Hall</.link>
          under "Guild Charters".
        </p>
        <p class="text-sm text-muted-foreground">
          To inject a charter into a quest, add a
          <code class="bg-muted px-1 rounded">guild_charter</code> context provider with
          <code class="bg-muted px-1 rounded">guild_name</code> set to the guild's name.
        </p>
      </section>

      <section>
        <h2 class="text-xl font-semibold mb-3">Model Fallback Chains</h2>
        <p class="text-sm text-muted-foreground mb-3">
          When Ollama fails for a member's assigned model, ExCalibur automatically retries with models
          from the configured fallback chain. Configure in
          <code class="bg-muted px-1 rounded">config/config.exs</code>:
        </p>
        <pre class="bg-muted rounded p-4 text-xs overflow-x-auto">{@fallback_snippet}</pre>
        <p class="text-sm text-muted-foreground mt-2">
          The assigned model is tried first. If it fails, models from the chain are tried in order.
          If all fail, the member abstains.
        </p>
      </section>

      <section>
        <h2 class="text-xl font-semibold mb-3">Member Trust Scores</h2>
        <p class="text-sm text-muted-foreground mb-3">
          After each quest run, members whose individual verdict contradicts the aggregated step verdict
          have their trust score decayed (×0.97). Scores start at 1.0 and are visible in the
          <.link navigate={~p"/lodge"} class="underline">Lodge</.link> under "Member Trust".
        </p>
        <p class="text-sm text-muted-foreground">
          Color coding: green ≥ 0.9 · yellow ≥ 0.75 · red below 0.75.
          Use trust scores to identify members whose judgement consistently diverges from consensus.
        </p>
      </section>
    </div>
    """
  end
end
