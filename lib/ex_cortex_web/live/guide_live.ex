defmodule ExCortexWeb.GuideLive do
  @moduledoc false
  use ExCortexWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Guide")}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-8 px-4 space-y-12">
      <div>
        <h1 class="text-3xl font-bold mb-2">How ExCortex Works</h1>
        <p class="text-muted-foreground text-base">
          A plain-English guide to what everything does and why it's useful.
          No technical knowledge required.
        </p>
      </div>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Wonder — Quick questions, no context</h2>
        <p class="text-base text-muted-foreground">
          <.link navigate={~p"/wonder"} class="underline text-foreground">Wonder</.link> is
          the simplest way to ask a question. Type something, get an answer — no data lookup,
          no knowledge-base search. It's a direct conversation with the underlying AI model.
        </p>
        <p class="text-base text-muted-foreground">
          Use Wonder when you want a quick opinion, a definition, help drafting text, or
          anything where your stored knowledge isn't relevant. Every question and answer is
          saved as a Thought so you can find it later.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Muse — Data-grounded Q&amp;A</h2>
        <p class="text-base text-muted-foreground">
          <.link navigate={~p"/muse"} class="underline text-foreground">Muse</.link> works
          like Wonder but smarter — before answering, it searches your
          <.link navigate={~p"/memory"} class="underline text-foreground">Memory</.link>
          for relevant engrams and uses them as context. This means answers are grounded in
          what your system actually knows, not just general AI knowledge.
        </p>
        <p class="text-base text-muted-foreground">
          Ask Muse when you want answers that reference your own data — project notes,
          past analyses, reports your team has produced. The more engrams you have stored,
          the more useful Muse becomes.
        </p>
        <p class="text-base text-muted-foreground">
          There's also a quick-muse bar on the
          <.link navigate={~p"/cortex"} class="underline text-foreground">Cortex</.link>
          dashboard so you can ask a grounded question without leaving home base.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Thoughts — Your question history</h2>
        <p class="text-base text-muted-foreground">
          Every question you ask through Wonder or Muse is saved as a
          <strong>Thought</strong>. The
          <.link navigate={~p"/thoughts"} class="underline text-foreground">Thoughts</.link>
          screen lets you browse, search, and revisit past questions and answers.
        </p>
        <p class="text-base text-muted-foreground">
          Think of it as a search history that actually keeps the answers. Useful when you
          remember asking something last week but can't recall the details.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Ruminations — Asking your team a question</h2>
        <p class="text-base text-muted-foreground">
          A <strong>Rumination</strong> is a job you give to your AI helpers. You describe what you want
          checked or written, choose which helpers should work on it, and ExCortex sends it to them
          and collects their answers.
        </p>
        <p class="text-base text-muted-foreground">
          Think of it like sending a memo to your team and waiting for their responses — except it
          all happens in seconds.
        </p>
        <p class="text-base text-muted-foreground">
          You can run a rumination manually any time, set it to run on a schedule (like every morning at
          9am), or have it trigger automatically when new information arrives.
        </p>
        <p class="text-base text-muted-foreground">
          Some ruminations produce a verdict (pass / warn / fail). Others produce a written output — a
          summary, a report, an analysis — which gets saved automatically to the
          <.link navigate={~p"/memory"} class="underline text-foreground">Memory</.link>
          for your whole team to see and build on later.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Ruminations — Chaining steps together</h2>
        <p class="text-base text-muted-foreground">
          Sometimes one step isn't enough — you want the result of the first step to feed into the next.
          That's what a <strong>Rumination</strong> is for.
        </p>
        <p class="text-base text-muted-foreground">
          Imagine asking one helper to summarise today's news, then passing that summary to a second
          helper who decides whether it affects your business. Each step gets a full briefing on what
          the previous step found, so nothing gets lost in the handoff.
        </p>
        <p class="text-base text-muted-foreground">
          You create a Rumination in the
          <.link navigate={~p"/ruminations"} class="underline text-foreground">Ruminations</.link>
          page, add the steps in order, and ExCortex runs them one after another automatically.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Branch Steps — Running jobs side-by-side</h2>
        <p class="text-base text-muted-foreground">
          Inside a Rumination, you can have one step that runs several checks <em>at the same time</em>
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
        <h2 class="text-xl font-semibold">Neurons — Your AI helpers</h2>
        <p class="text-base text-muted-foreground">
          <strong>Neurons</strong> are the individual AI helpers that do the actual work. Each neuron
          has a name, a specialty, and a skill level — <em>Apprentice</em>, <em>Journeyman</em>,
          or <em>Master</em>.
        </p>
        <p class="text-base text-muted-foreground">
          Higher-ranked neurons use more capable AI models, which generally means better quality
          answers but also more time and resources. You wouldn't send a Master to check your grocery
          list, just as you wouldn't send an Apprentice to review a legal contract.
        </p>
        <p class="text-base text-muted-foreground">
          You manage your neurons in the
          <.link
            navigate={~p"/neurons"}
            class="underline text-foreground"
          >
            Neurons
          </.link>
          page.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">The Challenger — Your built-in sceptic</h2>
        <p class="text-base text-muted-foreground">
          The <strong>Challenger</strong> is a special helper whose entire job is to push back.
          If another helper says "looks good", the Challenger asks "but what's your proof?"
        </p>
        <p class="text-base text-muted-foreground">
          It's useful as a final check in a Rumination — after everyone else has weighed in, the
          Challenger reviews all the findings and will only agree if it sees real, specific evidence.
          Vague reassurances don't satisfy it.
        </p>
        <p class="text-base text-muted-foreground">
          You add the Challenger to a rumination's team just like any other neuron.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Skill requirements — Sending the right helper</h2>
        <p class="text-base text-muted-foreground">
          You can mark a Rumination as requiring a minimum skill level. If none of your active helpers
          meet that standard, the rumination simply won't run — rather than giving you a poor-quality answer.
        </p>
        <p class="text-base text-muted-foreground">
          Think of it like a job posting that says "Senior experience required." ExCortex checks
          before starting and lets you know if your team isn't qualified yet.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Pathways — Your house rules</h2>
        <p class="text-base text-muted-foreground">
          A <strong>Pathway</strong> is a set of standing instructions that every helper reads
          before they start any job. Think of it as pinning a note to the break room wall: "In this
          cluster, we always respond formally" or "Never recommend a product we don't carry."
        </p>
        <p class="text-base text-muted-foreground">
          You write the pathway once, and every helper automatically sees it on every job — no need
          to repeat yourself. Edit or add pathways at the bottom of the
          <.link navigate={~p"/neurons"} class="underline text-foreground">Neurons</.link>
          page.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Backup AI models — Always a plan B</h2>
        <p class="text-base text-muted-foreground">
          Each helper uses a specific AI model under the hood. Sometimes that model isn't available
          or doesn't respond. ExCortex can automatically try a list of backup models instead of
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
          Over time, ExCortex keeps a quiet tally: when a helper's opinion goes against the group's
          final decision repeatedly, their <strong>Trust Score</strong> edges down. When they agree
          with the group, it stays put.
        </p>
        <p class="text-base text-muted-foreground">
          It's not a punishment — it's information. A low score might mean a helper is too
          conservative, too lenient, or just misconfigured. You can see the scores in the
          <.link navigate={~p"/cortex"} class="underline text-foreground">Cortex</.link>
          under
          "Neuron Trust" and use them to decide whether to retrain or replace a helper.
        </p>
        <p class="text-base text-muted-foreground">
          Green means the helper is consistently in line with the team.
          Yellow means occasional disagreements worth watching.
          Red means this helper frequently goes its own way — worth investigating.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">Memory — Your cluster's shared notebook</h2>
        <p class="text-base text-muted-foreground">
          The <.link navigate={~p"/memory"} class="underline text-foreground">Memory</.link> is
          where your cluster's knowledge accumulates. Every time a rumination produces a written output, it
          lands here as an engram. Over time it becomes a living record of everything your helpers
          have figured out — reports, summaries, analyses, decisions.
        </p>
        <p class="text-base text-muted-foreground">
          You can also write engrams yourself, the same way you'd jot a note in a shared notebook.
          Each engram can have tags (like sticky-note labels) and an importance rating from 1 to 5,
          so the most critical findings don't get buried under routine updates.
        </p>
        <p class="text-base text-muted-foreground">
          <strong>The Augury</strong> sits pinned at the top — your cluster's current "big picture"
          read on the world. Think of it as the one-page briefing you'd hand someone walking in the
          door. Ruminations set to "replace" mode keep it current automatically, so it always reflects
          your latest thinking without needing you to update it by hand.
        </p>
        <p class="text-base text-muted-foreground">
          The really useful part: your helpers can <em>read</em> from Memory before they start
          working. You can configure any rumination to pull in recent engrams first, so your helpers
          arrive already briefed on what the cluster has learned. It's the difference between asking
          a new temp and asking someone who's been on the team for months.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-xl font-semibold">The Cortex — Your dashboard</h2>
        <p class="text-base text-muted-foreground">
          The <.link navigate={~p"/cortex"} class="underline text-foreground">Cortex</.link> is your
          home base. It shows recent activity, outcomes, trust scores, and any suggestions the system
          has made for improving how things are set up.
        </p>
        <p class="text-base text-muted-foreground">
          If you're not sure where to start, the Cortex is a good first stop each day.
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
          <h3 class="font-semibold text-sm">Ruminations &amp; RuminationRunner</h3>
          <p class="text-sm text-muted-foreground">
            Ruminations are Ecto-backed records with a <code class="bg-muted px-1 rounded">steps</code>
            jsonb array. <code class="bg-muted px-1 rounded">RuminationRunner.run/2</code>
            resolves each <code class="bg-muted px-1 rounded">step_id</code>, and threads output as a structured
            handoff block into the next step's input. The final step's result is returned.
            Source-triggered ruminations go through <code class="bg-muted px-1 rounded">RuminationDebouncer.enqueue_rumination/3</code>;
            scheduled ones are picked up each minute by <code class="bg-muted px-1 rounded">ScheduledRuminationRunner</code>.
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
            Configured via <code class="bg-muted px-1 rounded">config :ex_cortex, :model_fallback_chain, [...]</code>.
            <code class="bg-muted px-1 rounded">RuminationRunner.fallback_models_for/2</code>
            prepends the
            neuron's assigned model and deduplicates.
            <code class="bg-muted px-1 rounded">call_neuron/3</code>
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
          <h3 class="font-semibold text-sm">Pathway Context Provider</h3>
          <p class="text-sm text-muted-foreground">
            Pathways are stored in the <code class="bg-muted px-1 rounded">pathways</code>
            table (unique on <code class="bg-muted px-1 rounded">cluster_name</code>).
            Add
            <code class="bg-muted px-1 rounded">
              %&lbrace;"type" =&gt; "pathway", "cluster_name" =&gt; "..."&rbrace;
            </code>
            to a rumination's <code class="bg-muted px-1 rounded">context_providers</code>
            array and it
            will be prepended to every neuron's input via <code class="bg-muted px-1 rounded">ContextProvider.assemble/3</code>.
          </p>
        </div>

        <div class="space-y-2">
          <h3 class="font-semibold text-sm">Neuron Trust Scoring</h3>
          <p class="text-sm text-muted-foreground">
            <code class="bg-muted px-1 rounded">TrustScorer.record_run/1</code>
            is called after
            every verdict daydream. It fires a <code class="bg-muted px-1 rounded">Task.start/1</code>
            that iterates each step's results, comparing individual neuron verdicts against the
            aggregated step verdict. Contradicting neurons get
            <code class="bg-muted px-1 rounded">decay/1</code>
            called, which upserts into <code class="bg-muted px-1 rounded">member_trust_scores</code>
            with score × 0.97 and
            increments <code class="bg-muted px-1 rounded">decay_count</code>.
          </p>
        </div>

        <div class="space-y-2">
          <h3 class="font-semibold text-sm">Memory Context Provider</h3>
          <p class="text-sm text-muted-foreground">
            Artifact ruminations write to <code class="bg-muted px-1 rounded">engrams</code>
            via <code class="bg-muted px-1 rounded">Memory.write_artifact/2</code>. Write mode controls
            behaviour: <code class="bg-muted px-1 rounded">append</code>
            always inserts, <code class="bg-muted px-1 rounded">replace</code>
            upserts the rumination-owned entry
            (never overwrites <code class="bg-muted px-1 rounded">source: "manual"</code>),
            <code class="bg-muted px-1 rounded">both</code>
            does a replace on the pinned entry
            and also appends a dated log entry. Repetitive/garbled LLM output is rejected before
            insert via a word-repetition regex.
            The Augury is the first entry tagged <code class="bg-muted px-1 rounded">augury</code>,
            sorted by newest. PubSub broadcasts
            <code class="bg-muted px-1 rounded">&lbrace;:engram_updated, title&rbrace;</code>
            on write so MemoryLive updates live.
            The <code class="bg-muted px-1 rounded">memory</code>
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
          <h3 class="font-semibold text-sm">The Challenger Builtin Neuron</h3>
          <p class="text-sm text-muted-foreground">
            Resolved by <code class="bg-muted px-1 rounded">resolve_neurons("challenger")</code>
            in
            RuminationRunner. Backed by <code class="bg-muted px-1 rounded">Builtin.validators/0</code>
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
