defmodule ExCaliburWeb.GuideLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Guide")}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-8 px-4 space-y-12">
      <div>
        <h1 class="text-3xl font-bold mb-2">How ExCalibur Works</h1>
        <p class="text-muted-foreground text-base">
          A plain-English guide to what everything does and why it's useful.
          No technical knowledge required.
        </p>
      </div>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Quests — Asking your team a question</h2>
        <p class="text-base text-muted-foreground">
          A <strong>Quest</strong> is a job you give to your AI helpers. You describe what you want
          checked or written, choose which helpers should work on it, and ExCalibur sends it to them
          and collects their answers.
        </p>
        <p class="text-base text-muted-foreground">
          Think of it like sending a memo to your team and waiting for their responses — except it
          all happens in seconds.
        </p>
        <p class="text-base text-muted-foreground">
          You can run a quest manually any time, set it to run on a schedule (like every morning at
          9am), or have it trigger automatically when new information arrives.
        </p>
        <p class="text-base text-muted-foreground">
          Some quests produce a verdict (pass / warn / fail). Others produce a written output — a
          summary, a report, an analysis — which gets saved automatically to the
          <.link navigate={~p"/grimoire"} class="underline text-foreground">Grimoire</.link>
          for your whole team to see and build on later.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Quests — Chaining steps together</h2>
        <p class="text-base text-muted-foreground">
          Sometimes one step isn't enough — you want the result of the first step to feed into the next.
          That's what a <strong>Quest</strong> is for.
        </p>
        <p class="text-base text-muted-foreground">
          Imagine asking one helper to summarise today's news, then passing that summary to a second
          helper who decides whether it affects your business. Each step gets a full briefing on what
          the previous step found, so nothing gets lost in the handoff.
        </p>
        <p class="text-base text-muted-foreground">
          You create a Quest in the
          <.link navigate={~p"/quests"} class="underline text-foreground">Quests</.link>
          page, add the steps in order, and ExCalibur runs them one after another automatically.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Branch Steps — Running jobs side-by-side</h2>
        <p class="text-base text-muted-foreground">
          Inside a Quest, you can have one step that runs several checks <em>at the same time</em>
          rather than one after another. The app calls this a <strong>Branch</strong>
          step.
        </p>
        <p class="text-base text-muted-foreground">
          For example: one helper checks the tone of a document, another checks the facts, and a
          third checks for legal issues — all simultaneously. When they're all done, a fourth helper
          reads all three reports and gives you a final verdict.
        </p>
        <p class="text-base text-muted-foreground">
          This saves time when the checks are independent of each other.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Members — Your AI helpers</h2>
        <p class="text-base text-muted-foreground">
          <strong>Members</strong> are the individual AI helpers that do the actual work. Each member
          has a name, a specialty, and a skill level — <em>Apprentice</em>, <em>Journeyman</em>,
          or <em>Master</em>.
        </p>
        <p class="text-base text-muted-foreground">
          Higher-ranked members use more capable AI models, which generally means better quality
          answers but also more time and resources. You wouldn't send a Master to check your grocery
          list, just as you wouldn't send an Apprentice to review a legal contract.
        </p>
        <p class="text-base text-muted-foreground">
          You manage your members in the <.link
            navigate={~p"/guild-hall"}
            class="underline text-foreground"
          >Guild Hall</.link>.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">The Challenger — Your built-in sceptic</h2>
        <p class="text-base text-muted-foreground">
          The <strong>Challenger</strong> is a special helper whose entire job is to push back.
          If another helper says "looks good", the Challenger asks "but what's your proof?"
        </p>
        <p class="text-base text-muted-foreground">
          It's useful as a final check in a Campaign — after everyone else has weighed in, the
          Challenger reviews all the findings and will only agree if it sees real, specific evidence.
          Vague reassurances don't satisfy it.
        </p>
        <p class="text-base text-muted-foreground">
          You add the Challenger to a quest's team just like any other member.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Skill requirements — Sending the right helper</h2>
        <p class="text-base text-muted-foreground">
          You can mark a Quest as requiring a minimum skill level. If none of your active helpers
          meet that standard, the quest simply won't run — rather than giving you a poor-quality answer.
        </p>
        <p class="text-base text-muted-foreground">
          Think of it like a job posting that says "Senior experience required." ExCalibur checks
          before starting and lets you know if your team isn't qualified yet.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Guild Charters — Your house rules</h2>
        <p class="text-base text-muted-foreground">
          A <strong>Guild Charter</strong> is a set of standing instructions that every helper reads
          before they start any job. Think of it as pinning a note to the break room wall: "In this
          guild, we always respond formally" or "Never recommend a product we don't carry."
        </p>
        <p class="text-base text-muted-foreground">
          You write the charter once, and every helper automatically sees it on every job — no need
          to repeat yourself. Edit or add charters at the bottom of the
          <.link navigate={~p"/guild-hall"} class="underline text-foreground">Guild Hall</.link>
          page.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Backup AI models — Always a plan B</h2>
        <p class="text-base text-muted-foreground">
          Each helper uses a specific AI model under the hood. Sometimes that model isn't available
          or doesn't respond. ExCalibur can automatically try a list of backup models instead of
          giving up — like calling your second-choice supplier when the first one is out of stock.
        </p>
        <p class="text-base text-muted-foreground">
          This is configured by whoever set up the system, so you don't need to worry about it day
          to day — it just works quietly in the background.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Trust Scores — Tracking who gives good advice</h2>
        <p class="text-base text-muted-foreground">
          Over time, ExCalibur keeps a quiet tally: when a helper's opinion goes against the group's
          final decision repeatedly, their <strong>Trust Score</strong> edges down. When they agree
          with the group, it stays put.
        </p>
        <p class="text-base text-muted-foreground">
          It's not a punishment — it's information. A low score might mean a helper is too
          conservative, too lenient, or just misconfigured. You can see the scores in the
          <.link navigate={~p"/lodge"} class="underline text-foreground">Lodge</.link>
          under
          "Member Trust" and use them to decide whether to retrain or replace a helper.
        </p>
        <p class="text-base text-muted-foreground">
          Green means the helper is consistently in line with the team.
          Yellow means occasional disagreements worth watching.
          Red means this helper frequently goes its own way — worth investigating.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">The Grimoire — Your guild's shared notebook</h2>
        <p class="text-base text-muted-foreground">
          The <.link navigate={~p"/grimoire"} class="underline text-foreground">Grimoire</.link> is
          where your guild's knowledge accumulates. Every time a quest produces a written output, it
          lands here as an entry. Over time it becomes a living record of everything your helpers
          have figured out — reports, summaries, analyses, decisions.
        </p>
        <p class="text-base text-muted-foreground">
          You can also write entries yourself, the same way you'd jot a note in a shared notebook.
          Each entry can have tags (like sticky-note labels) and an importance rating from 1 to 5,
          so the most critical findings don't get buried under routine updates.
        </p>
        <p class="text-base text-muted-foreground">
          <strong>The Augury</strong> sits pinned at the top — your guild's current "big picture"
          read on the world. Think of it as the one-page briefing you'd hand someone walking in the
          door. Quests set to "replace" mode keep it current automatically, so it always reflects
          your latest thinking without needing you to update it by hand.
        </p>
        <p class="text-base text-muted-foreground">
          The really useful part: your helpers can <em>read</em> the Grimoire before they start
          working. You can configure any quest to pull in recent entries first, so your helpers
          arrive already briefed on what the guild has learned. It's the difference between asking
          a new temp and asking someone who's been on the team for months.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">The Lodge — Your dashboard</h2>
        <p class="text-base text-muted-foreground">
          The <.link navigate={~p"/lodge"} class="underline text-foreground">Lodge</.link> is your
          home base. It shows recent activity, outcomes, trust scores, and any suggestions the system
          has made for improving how things are set up.
        </p>
        <p class="text-base text-muted-foreground">
          If you're not sure where to start, the Lodge is a good first stop each day.
        </p>
      </section>

      <hr class="border-border" />

      <section class="space-y-6">
        <div>
          <h2 class="text-xl font-semibold mb-1">Technical Reference</h2>
          <p class="text-sm text-muted-foreground">
            For the developer in the room. Accurate details on how each feature is wired together.
          </p>
        </div>

        <div class="space-y-2">
          <h3 class="font-semibold text-sm">Quests &amp; QuestRunner</h3>
          <p class="text-sm text-muted-foreground">
            Quests are Ecto-backed records with a <code class="bg-muted px-1 rounded">steps</code>
            jsonb array. <code class="bg-muted px-1 rounded">QuestRunner.run/2</code>
            resolves each <code class="bg-muted px-1 rounded">step_id</code>, and threads output as a structured
            handoff block into the next step's input. The final step's result is returned.
            Source-triggered quests go through <code class="bg-muted px-1 rounded">QuestDebouncer.enqueue_quest/3</code>;
            scheduled ones are picked up each minute by <code class="bg-muted px-1 rounded">ScheduledQuestRunner</code>.
          </p>
        </div>

        <div class="space-y-2">
          <h3 class="font-semibold text-sm">Branch Steps</h3>
          <p class="text-sm text-muted-foreground">
            A step with <code class="bg-muted px-1 rounded">"type" =&gt; "branch"</code>
            runs its <code class="bg-muted px-1 rounded">steps</code>
            list concurrently via <code class="bg-muted px-1 rounded">Task.async_stream/3</code>
            (120s timeout), then
            passes all results through
            <code class="bg-muted px-1 rounded">combine_branch_results/2</code>
            into the <code class="bg-muted px-1 rounded">synthesizer</code>
            step.
          </p>
        </div>

        <div class="space-y-2">
          <h3 class="font-semibold text-sm">Model Fallback Chains</h3>
          <p class="text-sm text-muted-foreground">
            Configured via <code class="bg-muted px-1 rounded">config :ex_calibur, :model_fallback_chain, [...]</code>.
            <code class="bg-muted px-1 rounded">QuestRunner.fallback_models_for/2</code>
            prepends the
            member's assigned model and deduplicates.
            <code class="bg-muted px-1 rounded">call_member/3</code>
            uses <code class="bg-muted px-1 rounded">Enum.reduce_while/3</code>
            to halt on the first
            successful Ollama response.
          </p>
        </div>

        <div class="space-y-2">
          <h3 class="font-semibold text-sm">Rank-Gated Eligibility</h3>
          <p class="text-sm text-muted-foreground">
            Steps with a non-nil <code class="bg-muted px-1 rounded">min_rank</code>
            field hit a
            guard clause in <code class="bg-muted px-1 rounded">StepRunner.run/2</code>
            that queries <code class="bg-muted px-1 rounded">excellence_members</code>
            for any active role whose <code class="bg-muted px-1 rounded">config-&gt;&gt;'rank'</code>
            is in the eligible set.
            Returns
            <code class="bg-muted px-1 rounded">
              &lbrace;:error, &lbrace;:rank_insufficient, reason&rbrace;&rbrace;
            </code>
            if none found.
          </p>
        </div>

        <div class="space-y-2">
          <h3 class="font-semibold text-sm">Guild Charter Context Provider</h3>
          <p class="text-sm text-muted-foreground">
            Charters are stored in the <code class="bg-muted px-1 rounded">guild_charters</code>
            table (unique on <code class="bg-muted px-1 rounded">guild_name</code>).
            Add
            <code class="bg-muted px-1 rounded">
              %&lbrace;"type" =&gt; "guild_charter", "guild_name" =&gt; "..."&rbrace;
            </code>
            to a quest's <code class="bg-muted px-1 rounded">context_providers</code>
            array and it
            will be prepended to every member's input via <code class="bg-muted px-1 rounded">ContextProvider.assemble/3</code>.
          </p>
        </div>

        <div class="space-y-2">
          <h3 class="font-semibold text-sm">Member Trust Scoring</h3>
          <p class="text-sm text-muted-foreground">
            <code class="bg-muted px-1 rounded">TrustScorer.record_run/1</code>
            is called after
            every verdict quest run. It fires a
            <code class="bg-muted px-1 rounded">Task.start/1</code>
            that iterates each step's results, comparing individual member verdicts against the
            aggregated step verdict. Contradicting members get
            <code class="bg-muted px-1 rounded">decay/1</code>
            called, which upserts into <code class="bg-muted px-1 rounded">member_trust_scores</code>
            with score × 0.97 and
            increments <code class="bg-muted px-1 rounded">decay_count</code>.
          </p>
        </div>

        <div class="space-y-2">
          <h3 class="font-semibold text-sm">Grimoire &amp; Lore Context Provider</h3>
          <p class="text-sm text-muted-foreground">
            Artifact quests write to <code class="bg-muted px-1 rounded">lore_entries</code>
            via <code class="bg-muted px-1 rounded">Lore.write_artifact/2</code>. Write mode controls
            behaviour: <code class="bg-muted px-1 rounded">append</code>
            always inserts, <code class="bg-muted px-1 rounded">replace</code>
            upserts the quest-owned entry
            (never overwrites <code class="bg-muted px-1 rounded">source: "manual"</code>),
            <code class="bg-muted px-1 rounded">both</code>
            does a replace on the pinned entry
            and also appends a dated log entry. Repetitive/garbled LLM output is rejected before
            insert via a word-repetition regex.
            The Augury is the first entry tagged <code class="bg-muted px-1 rounded">augury</code>,
            sorted by newest. PubSub broadcasts
            <code class="bg-muted px-1 rounded">&lbrace;:lore_updated, title&rbrace;</code>
            on write so GrimoireLive updates live.
            The <code class="bg-muted px-1 rounded">lore</code>
            context provider pulls entries by
            tag + sort into the prompt preamble (1 500-char total cap). Sort
            <code class="bg-muted px-1 rounded">top</code>
            blends <code class="bg-muted px-1 rounded">importance</code>
            and <code class="bg-muted px-1 rounded">newest</code>
            halves, deduped, to prevent
            high-signal historical entries from being crowded out by recent noise.
          </p>
        </div>

        <div class="space-y-2">
          <h3 class="font-semibold text-sm">The Challenger Builtin Member</h3>
          <p class="text-sm text-muted-foreground">
            Resolved by <code class="bg-muted px-1 rounded">resolve_members("challenger")</code>
            in
            QuestRunner. Backed by
            <code class="bg-muted px-1 rounded">BuiltinMember.validators/0</code>
            — category <code class="bg-muted px-1 rounded">:validator</code>, uses the journeyman
            model from <code class="bg-muted px-1 rounded">@default_ranks</code>. Prompt is hardcoded
            to demand specific evidence and default to fail.
          </p>
        </div>
      </section>
    </div>
    """
  end
end
