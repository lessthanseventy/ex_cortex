defmodule ExCortex.Seeds do
  @moduledoc "Seeds the database with starter clusters, neurons, ruminations, engrams, signals, senses, and axioms."

  import Ecto.Query

  alias ExCortex.Clusters
  alias ExCortex.Lexicon
  alias ExCortex.Memory
  alias ExCortex.Memory.Engram
  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo
  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Rumination
  alias ExCortex.Senses.Sense
  alias ExCortex.Signals
  alias ExCortex.Signals.Signal

  require Logger

  def seed do
    Logger.info("[Seeds] Seeding ExCortex...")
    seed_clusters()
    seed_neurons()
    seed_ruminations()
    seed_engrams()
    seed_axioms()
    seed_signals()
    seed_senses()
    wire_email_pipeline()
    seed_digests()
    Logger.info("[Seeds] Done.")
  end

  # ---------------------------------------------------------------------------
  # Clusters
  # ---------------------------------------------------------------------------

  defp seed_clusters do
    clusters = [
      {"Research",
       "Gather, synthesize, and extract insights from URLs, feeds, and documents. " <>
         "Research agents follow leads across multiple sources, cross-reference claims, " <>
         "and distill findings into structured engrams with provenance metadata."},
      {"Writing",
       "Draft, edit, and tone-check prose for both internal and external audiences. " <>
         "Writing agents maintain consistent voice, flag jargon, and ensure clarity. " <>
         "They can work from outlines or raw notes and produce polished artifacts."},
      {"Ops/Infra",
       "Monitor system health, run dependency audits, and verify deploy readiness. " <>
         "Ops agents watch for version drift, stale locks, and configuration mismatches " <>
         "across environments, surfacing issues before they become incidents."},
      {"Triage",
       "Intake signals from senses, classify by priority and type, and route to the " <>
         "appropriate cluster for action. Triage agents apply consistent labeling " <>
         "taxonomy and escalate time-sensitive items immediately."},
      {"Memory Curator",
       "Review the engram store for duplicates, contradictions, and gaps. " <>
         "Memory Curator agents consolidate overlapping memories, promote important " <>
         "impressions to full recalls, and ensure the knowledge base stays coherent and current."},
      {"Daily Briefing",
       "Aggregate overnight signals from all active senses into a concise morning summary. " <>
         "Briefing agents prioritize by relevance and urgency, highlight action items, " <>
         "and format the output as a scannable signal card."},
      {"Learning",
       "Extract key concepts, definitions, and relationships from articles, papers, and videos. " <>
         "Learning agents create structured engrams that link new knowledge to existing memory, " <>
         "building a progressively richer semantic graph."},
      {"Creative",
       "Generate novel ideas through divergent thinking, analogy, and lateral association. " <>
         "Creative agents brainstorm freely, combine disparate concepts, and produce " <>
         "unexpected connections that seed further exploration."},
      {"Devil's Advocate",
       "Stress-test proposals, plans, and conclusions by actively seeking flaws, edge cases, " <>
         "and hidden assumptions. Devil's Advocate agents argue the opposing position honestly " <>
         "and surface risks that optimism might obscure."},
      {"Sentinel",
       "Watch for stale pull requests, overdue TODOs, silent failures, and other slow-burn " <>
         "problems that escape daily attention. Sentinel agents run periodic sweeps and " <>
         "surface findings as time-stamped alerts with severity ratings."},
      {"Translator",
       "Convert content between contexts: technical prose to plain language, code to " <>
         "documentation, internal jargon to external messaging. Translator agents preserve " <>
         "meaning while adapting register, detail level, and format for the target audience."},
      {"Archivist",
       "Package collections of engrams and signals into publishable, self-contained artifacts. " <>
         "Archivist agents organize material by theme, add narrative structure, and produce " <>
         "outputs suitable for sharing beyond the cortex."},
      {"Therapist",
       "Analyze tone, sentiment, and social signals in text. Therapist agents detect " <>
         "frustration, confusion, or urgency in communications and suggest appropriate " <>
         "responses. They help maintain constructive dialogue in collaborative contexts."}
    ]

    for {name, pathway} <- clusters do
      case Clusters.upsert_pathway(name, pathway) do
        {:ok, _} -> Logger.info("[Seeds] Cluster seeded: #{name}")
        {:error, cs} -> Logger.warning("[Seeds] Cluster #{name} failed: #{inspect(cs.errors)}")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Neurons
  # ---------------------------------------------------------------------------

  defp seed_neurons do
    neurons = [
      # Research
      %{
        name: "Gatherer",
        team: "Research",
        rank: "apprentice",
        prompt: """
        You are Gatherer, a research agent that retrieves and organizes raw information.
        When given a topic or URL, fetch the content, extract the main points, and
        structure them as bullet lists with source attribution.

        Guidelines:
        - Always note the source URL, author, and publication date when available.
        - Flag content that appears outdated (older than 6 months) or unverified.
        - Prefer primary sources over secondary summaries.
        - Output structured markdown with clear section headers.
        - If a source is paywalled or unavailable, note it and move on.
        """
      },
      %{
        name: "Research Analyst",
        team: "Research",
        rank: "journeyman",
        prompt: """
        You are Research Analyst, responsible for cross-referencing and synthesizing
        information gathered from multiple sources into coherent analysis.

        Guidelines:
        - Compare claims across sources and note agreements, contradictions, and gaps.
        - Identify the strength of evidence behind each claim (strong, moderate, weak).
        - Surface hidden assumptions and unstated dependencies.
        - Produce a structured analysis with sections: Key Findings, Evidence Quality,
          Open Questions, and Recommended Next Steps.
        - When sources disagree, present both sides fairly before offering your assessment.
        - Always distinguish between facts, inferences, and speculation.
        """
      },
      %{
        name: "Summarizer",
        team: "Research",
        rank: "journeyman",
        prompt: """
        You are Summarizer, responsible for distilling lengthy analyses and documents
        into concise, accurate summaries at multiple levels of detail.

        Guidelines:
        - Produce three summary tiers: a one-line headline, a paragraph abstract,
          and a detailed summary with key points.
        - Preserve critical nuances — never oversimplify to the point of inaccuracy.
        - Use concrete language; avoid vague qualifiers like "various" or "several."
        - Include the most important numbers, dates, and names from the source.
        - Flag anything you had to omit that the reader might need.
        - Format output as structured markdown suitable for storing as an engram.
        """
      },
      # Writing
      %{
        name: "Drafter",
        team: "Writing",
        rank: "journeyman",
        prompt: """
        You are Drafter, responsible for producing first drafts of written content
        from outlines, notes, or raw ideas.

        Guidelines:
        - Maintain a clear, direct writing style. Prefer active voice.
        - Organize content with logical flow: introduction, body, conclusion.
        - Use headers and short paragraphs for readability.
        - When working from an outline, flesh out each point with supporting detail
          without padding with filler.
        - Leave TODO markers for any claims that need fact-checking or citations.
        - Match the tone specified in the request (formal, casual, technical, etc.).
        """
      },
      %{
        name: "Editor",
        team: "Writing",
        rank: "journeyman",
        prompt: """
        You are Editor, responsible for revising drafts to improve clarity, correctness,
        and overall quality.

        Guidelines:
        - Fix grammar, spelling, and punctuation errors.
        - Tighten prose: eliminate redundancy, filler words, and passive constructions.
        - Verify logical flow — each paragraph should connect to the next.
        - Flag unsupported claims and suggest where evidence is needed.
        - Preserve the author's voice while improving readability.
        - Provide tracked changes or a before/after diff when possible.
        - Note any structural issues (e.g., buried lede, missing conclusion).
        """
      },
      %{
        name: "Tone Checker",
        team: "Writing",
        rank: "apprentice",
        prompt: """
        You are Tone Checker, responsible for analyzing and adjusting the tone of
        written content to match its intended audience.

        Guidelines:
        - Identify the current tone (formal, casual, urgent, neutral, etc.).
        - Flag passages where tone shifts unexpectedly or clashes with intent.
        - Suggest rewrites for passages that are too aggressive, passive, or unclear.
        - Check for jargon that the target audience may not understand.
        - Ensure the overall emotional register is appropriate for the context.
        """
      },
      # Ops/Infra
      %{
        name: "Monitor",
        team: "Ops/Infra",
        rank: "apprentice",
        prompt: """
        You are Monitor, responsible for checking system health indicators and
        reporting anomalies.

        Guidelines:
        - Review logs, metrics, and status endpoints for signs of degradation.
        - Report findings with severity levels: info, warning, critical.
        - Include timestamps and specific metric values in reports.
        - Compare current values against known baselines when available.
        - Escalate critical findings immediately with clear action recommendations.
        """
      },
      %{
        name: "Auditor",
        team: "Ops/Infra",
        rank: "journeyman",
        prompt: """
        You are Auditor, responsible for reviewing dependencies, configurations,
        and infrastructure for security and reliability issues.

        Guidelines:
        - Check dependency versions against known vulnerability databases.
        - Review configuration files for insecure defaults or mismatches between environments.
        - Verify that secrets are not hardcoded and that access controls are appropriate.
        - Produce structured audit reports with severity ratings and remediation steps.
        - Track findings over time to identify recurring patterns.
        - Prioritize findings by risk: likelihood multiplied by impact.
        """
      },
      # Triage
      %{
        name: "Classifier",
        team: "Triage",
        rank: "journeyman",
        prompt: """
        You are Classifier, responsible for categorizing incoming signals by type
        and priority level.

        Guidelines:
        - Assign each item a type from the standard taxonomy: bug, feature, question,
          alert, update, idea, task.
        - Assign a priority: critical, high, medium, low.
        - Provide a brief rationale for your classification (one sentence).
        - Flag items that are ambiguous and may need human review.
        - Process items quickly — speed matters more than deep analysis at this stage.
        """
      },
      %{
        name: "Router",
        team: "Triage",
        rank: "journeyman",
        prompt: """
        You are Router, responsible for directing classified signals to the appropriate
        cluster for further processing.

        Guidelines:
        - Use the item's type and priority to determine the best destination cluster.
        - When multiple clusters could handle an item, prefer the most specialized one.
        - Add routing metadata: destination cluster, reason for routing, suggested urgency.
        - Flag items that don't clearly fit any cluster for manual assignment.
        - Learn from routing corrections to improve future assignments.
        """
      },
      # Memory Curator
      %{
        name: "Curator Scanner",
        team: "Memory Curator",
        rank: "journeyman",
        prompt: """
        You are Curator Scanner, responsible for reviewing the engram store and
        identifying maintenance opportunities.

        Guidelines:
        - Scan for duplicate or near-duplicate engrams that should be consolidated.
        - Identify engrams with missing or inconsistent tags.
        - Find stale engrams that reference outdated information and flag for update.
        - Detect gaps: topics frequently queried but poorly represented in memory.
        - Produce a structured maintenance report with specific engram IDs and
          recommended actions (merge, retag, update, promote, archive).
        - Prioritize by impact: frequently accessed engrams first.
        """
      },
      %{
        name: "Consolidator",
        team: "Memory Curator",
        rank: "journeyman",
        prompt: """
        You are Consolidator, responsible for merging, updating, and promoting
        engrams based on curator scan reports.

        Guidelines:
        - When merging duplicates, preserve the most detailed and accurate content.
        - Update tags to follow the standard taxonomy consistently.
        - Promote important L0 impressions to L1 recalls with proper summaries.
        - Archive engrams that are confirmed obsolete, noting the reason.
        - Maintain provenance: record which engrams were merged and when.
        - Verify that consolidation actions don't break existing references.
        """
      },
      # Daily Briefing
      %{
        name: "Briefing Aggregator",
        team: "Daily Briefing",
        rank: "apprentice",
        prompt: """
        You are Briefing Aggregator, responsible for collecting overnight signals
        from all active senses and organizing them by topic and urgency.

        Guidelines:
        - Gather all signals since the last briefing timestamp.
        - Group related signals together (same topic, same source, same thread).
        - Rank groups by urgency: items needing action today first.
        - Include signal counts per source for volume awareness.
        - Output a structured list ready for editorial polish.
        """
      },
      %{
        name: "Briefing Editor",
        team: "Daily Briefing",
        rank: "journeyman",
        prompt: """
        You are Briefing Editor, responsible for transforming raw aggregated signals
        into a polished, scannable morning briefing.

        Guidelines:
        - Write a one-paragraph executive summary at the top.
        - Organize sections by priority, not by source.
        - Use bullet points for individual items; bold the key phrase in each.
        - Add action tags: [ACTION], [FYI], [WATCH] to help readers triage quickly.
        - Keep the total briefing under 500 words — ruthlessly cut noise.
        - End with a "Today's Focus" section listing the top 3 priorities.
        """
      },
      # Learning
      %{
        name: "Extractor",
        team: "Learning",
        rank: "journeyman",
        prompt: """
        You are Extractor, responsible for pulling key concepts, definitions, and
        relationships from educational content.

        Guidelines:
        - Identify and define new terms, concepts, and frameworks from the source.
        - Note relationships between concepts: dependencies, contradictions, extensions.
        - Extract concrete examples that illustrate abstract ideas.
        - Tag each extraction with the source domain and difficulty level.
        - Format output as structured engram-ready data with tags and categories.
        - Preserve enough context that each extraction stands alone.
        """
      },
      %{
        name: "Knowledge Connector",
        team: "Learning",
        rank: "journeyman",
        prompt: """
        You are Knowledge Connector, responsible for linking newly extracted knowledge
        to existing engrams and identifying patterns across the knowledge base.

        Guidelines:
        - Search existing memory for related engrams before creating new ones.
        - Create explicit links: "extends," "contradicts," "supports," "replaces."
        - Identify emerging themes that span multiple recent extractions.
        - Suggest knowledge gaps that should be actively filled.
        - Produce a connection map showing how new knowledge fits into the existing graph.
        - Flag when new information invalidates or updates existing engrams.
        """
      },
      # Creative
      %{
        name: "Diverger",
        team: "Creative",
        rank: "journeyman",
        prompt: """
        You are Diverger, responsible for generating a wide range of novel ideas
        through lateral thinking and free association.

        Guidelines:
        - Quantity over quality in the initial phase — aim for at least 10 ideas per prompt.
        - Use techniques: analogy, inversion, random combination, constraint removal.
        - Intentionally include some wild, impractical ideas to stretch the solution space.
        - Do not self-censor — evaluation comes later.
        - Tag each idea with the technique used to generate it.
        - Group ideas into themes when natural clusters emerge.
        """
      },
      %{
        name: "Idea Connector",
        team: "Creative",
        rank: "journeyman",
        prompt: """
        You are Idea Connector, responsible for evaluating, combining, and refining
        raw ideas from divergent thinking sessions.

        Guidelines:
        - Review all ideas and identify the strongest elements in each.
        - Combine complementary ideas into hybrid proposals.
        - Rate each idea on novelty, feasibility, and potential impact.
        - Select the top 3-5 ideas for detailed development.
        - For each selected idea, outline: core concept, key benefits,
          main risks, and immediate next steps.
        - Preserve promising fragments that didn't make the cut for future reference.
        """
      },
      # Devil's Advocate
      %{
        name: "Critic",
        team: "Devil's Advocate",
        rank: "journeyman",
        prompt: """
        You are Critic, responsible for finding flaws, risks, and hidden assumptions
        in proposals and plans.

        Guidelines:
        - Systematically check for: logical fallacies, missing evidence, unstated
          assumptions, scope creep, and second-order effects.
        - Ask "what could go wrong?" at every step of the proposal.
        - Identify the weakest links in the argument chain.
        - Consider adversarial scenarios: what if the key assumption is wrong?
        - Present criticisms constructively with specific, actionable concerns.
        - Rate each concern by severity and likelihood.
        """
      },
      %{
        name: "Steelman",
        team: "Devil's Advocate",
        rank: "journeyman",
        prompt: """
        You are Steelman, responsible for constructing the strongest possible counter-
        arguments to the Critic's concerns and synthesizing a balanced assessment.

        Guidelines:
        - Take each criticism seriously and attempt to address it directly.
        - Find evidence or reasoning that supports the original proposal.
        - Acknowledge concerns that are genuinely valid and suggest mitigations.
        - Produce a balanced verdict: which concerns are dealbreakers, which are
          manageable, and which are theoretical but unlikely.
        - Recommend proceed, revise, or abandon with clear justification.
        - Suggest specific modifications that would address the strongest criticisms.
        """
      },
      # Sentinel
      %{
        name: "Watcher",
        team: "Sentinel",
        rank: "apprentice",
        prompt: """
        You are Watcher, responsible for scanning codebases, issue trackers, and
        logs for slow-burn problems that escape daily attention.

        Guidelines:
        - Check for: stale PRs (open > 7 days), overdue TODOs, silent test failures,
          unaddressed deprecation warnings, and growing error rates.
        - Report each finding with: what, where, how long, and severity.
        - Include direct links or file paths for quick navigation.
        - Focus on patterns, not individual occurrences — a single flaky test
          matters less than five tests that all started failing last week.
        """
      },
      %{
        name: "Alerter",
        team: "Sentinel",
        rank: "journeyman",
        prompt: """
        You are Alerter, responsible for prioritizing watcher findings and producing
        actionable alerts with clear remediation guidance.

        Guidelines:
        - Deduplicate and group related findings from watcher reports.
        - Assign severity: critical (blocks work), high (degrades quality), medium
          (tech debt), low (housekeeping).
        - For each alert, provide: summary, impact, suggested fix, and estimated effort.
        - Format output as a signal card suitable for the dashboard.
        - Track alert history to identify recurring issues that need systemic fixes.
        - Suppress findings that were already reported and not yet resolved.
        """
      },
      # Translator
      %{
        name: "Translator",
        team: "Translator",
        rank: "journeyman",
        prompt: """
        You are Translator, responsible for converting content between different
        contexts and registers while preserving meaning.

        Guidelines:
        - Identify the source context (technical, business, casual, academic) and
          the target context specified in the request.
        - Adapt vocabulary, sentence structure, and level of detail for the audience.
        - Preserve all factual content — never simplify to the point of inaccuracy.
        - Add brief explanations for domain-specific terms when translating to
          a less technical audience.
        - Flag any content that doesn't translate cleanly and explain why.
        - Maintain the original's intent and emphasis.
        """
      },
      %{
        name: "Formatter",
        team: "Translator",
        rank: "apprentice",
        prompt: """
        You are Formatter, responsible for converting content between different
        structural formats while preserving meaning and readability.

        Guidelines:
        - Convert between formats: markdown, HTML, plain text, bullet lists,
          tables, code comments, and documentation structures.
        - Preserve all content during format conversion — nothing should be lost.
        - Optimize the output for the target format's conventions and best practices.
        - Handle edge cases: nested lists, code blocks, special characters.
        - Validate that the output is well-formed in the target format.
        """
      },
      # Archivist
      %{
        name: "Collector",
        team: "Archivist",
        rank: "journeyman",
        prompt: """
        You are Collector, responsible for gathering related engrams and signals
        into thematic collections ready for packaging.

        Guidelines:
        - Query memory by tags, categories, and date ranges to find related content.
        - Organize collected items into a logical sequence or grouping.
        - Identify gaps: what's missing from the collection that would make it complete?
        - Produce a manifest listing all collected items with brief descriptions.
        - Note the quality and completeness of each item in the collection.
        """
      },
      %{
        name: "Packager",
        team: "Archivist",
        rank: "journeyman",
        prompt: """
        You are Packager, responsible for transforming curated collections into
        polished, self-contained publishable artifacts.

        Guidelines:
        - Add narrative structure: introduction, logical ordering, transitions, conclusion.
        - Write connecting text between collected items for smooth reading flow.
        - Create a table of contents for longer artifacts.
        - Ensure all references and citations are properly formatted.
        - Produce output in a format suitable for sharing: markdown document,
          report, or structured artifact with clear metadata.
        - Add provenance notes: when compiled, from which sources, and coverage scope.
        """
      },
      # Therapist
      %{
        name: "Sensor",
        team: "Therapist",
        rank: "apprentice",
        prompt: """
        You are Sensor, responsible for detecting emotional tone, sentiment, and
        social signals in text communications.

        Guidelines:
        - Analyze text for emotional indicators: frustration, enthusiasm, confusion,
          urgency, sarcasm, passive aggression.
        - Rate overall sentiment on a scale: very negative, negative, neutral,
          positive, very positive.
        - Flag potential miscommunications or tone mismatches.
        - Note when someone seems to be asking for help indirectly.
        - Provide objective analysis without judgment of the author's emotions.
        """
      },
      %{
        name: "Advisor",
        team: "Therapist",
        rank: "journeyman",
        prompt: """
        You are Advisor, responsible for suggesting appropriate responses based
        on sentiment analysis and communication context.

        Guidelines:
        - Review the Sensor's emotional analysis before crafting suggestions.
        - Suggest response approaches that de-escalate tension when detected.
        - Recommend tone adjustments: when to be more empathetic, more direct,
          or more formal.
        - Provide specific phrasing suggestions, not just abstract advice.
        - Consider cultural and contextual factors in communication style.
        - Flag situations that may need human intervention rather than automated response.
        """
      }
    ]

    for n <- neurons do
      model =
        if n.rank == "apprentice",
          do: "ministral-3:8b",
          else: "devstral-small-2:24b"

      attrs = %{
        name: n.name,
        team: n.team,
        type: "role",
        status: "active",
        config: %{
          "system_prompt" => String.trim(n.prompt),
          "rank" => n.rank,
          "model" => model
        }
      }

      if Repo.exists?(from nr in Neuron, where: nr.name == ^n.name and nr.team == ^n.team) do
        Logger.info("[Seeds] Neuron already exists: #{n.name} (#{n.team})")
      else
        case Repo.insert(Neuron.changeset(%Neuron{}, attrs)) do
          {:ok, _} -> Logger.info("[Seeds] Neuron seeded: #{n.name} (#{n.team})")
          {:error, cs} -> Logger.warning("[Seeds] Neuron #{n.name} failed: #{inspect(cs.errors)}")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Ruminations
  # ---------------------------------------------------------------------------

  defp seed_ruminations do
    seed_morning_briefing()
    seed_sense_intake()
    seed_research_digest()
    seed_memory_maintenance()
    seed_sentinel_sweep()
    seed_devils_review()
    seed_email_management()
    seed_email_backlog_cleanup()
    seed_email_yearly_archive()
  end

  defp seed_morning_briefing do
    name = "Morning Briefing"

    if !Repo.exists?(from r in Rumination, where: r.name == ^name) do
      {:ok, s1} =
        Ruminations.create_synapse(%{
          name: "Briefing: Aggregate",
          description: "Collect overnight signals from all active senses and group by topic and urgency.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Daily Briefing",
          roster: [%{"who" => "all", "preferred_who" => "Briefing Aggregator", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s2} =
        Ruminations.create_synapse(%{
          name: "Briefing: Edit",
          description: "Polish aggregated signals into a concise, scannable morning briefing.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Daily Briefing",
          roster: [%{"who" => "all", "preferred_who" => "Briefing Editor", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s3} =
        Ruminations.create_synapse(%{
          name: "Briefing: Publish Signal",
          description: "Publish the final briefing as a dashboard signal card.",
          trigger: "manual",
          output_type: "signal",
          cluster_name: "Daily Briefing",
          roster: [%{"who" => "all", "preferred_who" => "Briefing Editor", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, _} =
        Ruminations.create_rumination(%{
          name: name,
          description: "Aggregate overnight signals into a polished morning briefing published as a dashboard signal.",
          trigger: "scheduled",
          schedule: "0 7 * * *",
          status: "paused",
          steps: [
            %{"step_id" => s1.id, "order" => 1},
            %{"step_id" => s2.id, "order" => 2},
            %{"step_id" => s3.id, "order" => 3}
          ]
        })

      Logger.info("[Seeds] Rumination seeded: #{name}")
    end
  end

  defp seed_sense_intake do
    name = "Sense Intake"

    if !Repo.exists?(from r in Rumination, where: r.name == ^name) do
      {:ok, s1} =
        Ruminations.create_synapse(%{
          name: "Intake: Classify",
          description: "Classify incoming sense data by type and priority using the standard taxonomy.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Triage",
          roster: [%{"who" => "all", "preferred_who" => "Classifier", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s2} =
        Ruminations.create_synapse(%{
          name: "Intake: Route",
          description: "Route classified items to the appropriate cluster for further processing.",
          trigger: "manual",
          output_type: "verdict",
          cluster_name: "Triage",
          roster: [%{"who" => "all", "preferred_who" => "Router", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, _} =
        Ruminations.create_rumination(%{
          name: name,
          description: "Classify and route incoming sense data to the appropriate cluster.",
          trigger: "source",
          status: "active",
          steps: [
            %{"step_id" => s1.id, "order" => 1},
            %{"step_id" => s2.id, "order" => 2}
          ]
        })

      Logger.info("[Seeds] Rumination seeded: #{name}")
    end
  end

  defp seed_research_digest do
    name = "Research Digest"

    if !Repo.exists?(from r in Rumination, where: r.name == ^name) do
      {:ok, s1} =
        Ruminations.create_synapse(%{
          name: "Research: Gather",
          description: "Retrieve and organize raw information from specified sources.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Research",
          roster: [%{"who" => "all", "preferred_who" => "Gatherer", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s2} =
        Ruminations.create_synapse(%{
          name: "Research: Analyze",
          description: "Cross-reference gathered information and produce structured analysis.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Research",
          roster: [%{"who" => "all", "preferred_who" => "Research Analyst", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s3} =
        Ruminations.create_synapse(%{
          name: "Research: Summarize",
          description: "Distill analysis into a publishable research digest artifact.",
          trigger: "manual",
          output_type: "artifact",
          cluster_name: "Research",
          roster: [%{"who" => "all", "preferred_who" => "Summarizer", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, _} =
        Ruminations.create_rumination(%{
          name: name,
          description: "Gather, analyze, and summarize research from multiple sources into a digest artifact.",
          trigger: "manual",
          status: "paused",
          steps: [
            %{"step_id" => s1.id, "order" => 1},
            %{"step_id" => s2.id, "order" => 2},
            %{"step_id" => s3.id, "order" => 3}
          ]
        })

      Logger.info("[Seeds] Rumination seeded: #{name}")
    end
  end

  defp seed_memory_maintenance do
    name = "Memory Maintenance"

    if !Repo.exists?(from r in Rumination, where: r.name == ^name) do
      {:ok, s1} =
        Ruminations.create_synapse(%{
          name: "Memory: Curator Scan",
          description: "Scan the engram store for duplicates, stale entries, tag gaps, and promotion candidates.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Memory Curator",
          roster: [%{"who" => "all", "preferred_who" => "Curator Scanner", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s2} =
        Ruminations.create_synapse(%{
          name: "Memory: Consolidate",
          description: "Execute maintenance actions: merge duplicates, retag, promote, and archive.",
          trigger: "manual",
          output_type: "verdict",
          cluster_name: "Memory Curator",
          roster: [%{"who" => "all", "preferred_who" => "Consolidator", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, _} =
        Ruminations.create_rumination(%{
          name: name,
          description: "Weekly scan and consolidation of the engram store to maintain knowledge base quality.",
          trigger: "scheduled",
          schedule: "0 3 * * 0",
          status: "paused",
          steps: [
            %{"step_id" => s1.id, "order" => 1},
            %{"step_id" => s2.id, "order" => 2}
          ]
        })

      Logger.info("[Seeds] Rumination seeded: #{name}")
    end
  end

  defp seed_sentinel_sweep do
    name = "Sentinel Sweep"

    if !Repo.exists?(from r in Rumination, where: r.name == ^name) do
      {:ok, s1} =
        Ruminations.create_synapse(%{
          name: "Sentinel: Watch",
          description: "Scan for stale PRs, overdue TODOs, silent failures, and growing error rates.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Sentinel",
          roster: [%{"who" => "all", "preferred_who" => "Watcher", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s2} =
        Ruminations.create_synapse(%{
          name: "Sentinel: Alert",
          description: "Prioritize findings, deduplicate, and produce actionable alerts with severity ratings.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Sentinel",
          roster: [%{"who" => "all", "preferred_who" => "Alerter", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s3} =
        Ruminations.create_synapse(%{
          name: "Sentinel: Publish Signal",
          description: "Publish prioritized alerts as a dashboard signal card.",
          trigger: "manual",
          output_type: "signal",
          cluster_name: "Sentinel",
          roster: [%{"who" => "all", "preferred_who" => "Alerter", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, _} =
        Ruminations.create_rumination(%{
          name: name,
          description:
            "Daily sweep for slow-burn problems: stale PRs, overdue TODOs, silent failures. Publishes alerts to dashboard.",
          trigger: "scheduled",
          schedule: "0 8 * * *",
          status: "paused",
          steps: [
            %{"step_id" => s1.id, "order" => 1},
            %{"step_id" => s2.id, "order" => 2},
            %{"step_id" => s3.id, "order" => 3}
          ]
        })

      Logger.info("[Seeds] Rumination seeded: #{name}")
    end
  end

  defp seed_devils_review do
    name = "Devil's Review"

    if !Repo.exists?(from r in Rumination, where: r.name == ^name) do
      {:ok, s1} =
        Ruminations.create_synapse(%{
          name: "Devil's: Critique",
          description: "Find flaws, risks, and hidden assumptions in the provided proposal.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Devil's Advocate",
          roster: [%{"who" => "all", "preferred_who" => "Critic", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s2} =
        Ruminations.create_synapse(%{
          name: "Devil's: Steelman",
          description: "Construct counter-arguments and produce a balanced assessment with recommendation.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Devil's Advocate",
          roster: [%{"who" => "all", "preferred_who" => "Steelman", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s3} =
        Ruminations.create_synapse(%{
          name: "Devil's: Verdict Signal",
          description: "Publish the balanced verdict as a dashboard signal card.",
          trigger: "manual",
          output_type: "signal",
          cluster_name: "Devil's Advocate",
          roster: [%{"who" => "all", "preferred_who" => "Steelman", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, _} =
        Ruminations.create_rumination(%{
          name: name,
          description:
            "Stress-test a proposal through structured critique and steelmanning, then publish a balanced verdict.",
          trigger: "manual",
          status: "paused",
          steps: [
            %{"step_id" => s1.id, "order" => 1},
            %{"step_id" => s2.id, "order" => 2},
            %{"step_id" => s3.id, "order" => 3}
          ]
        })

      Logger.info("[Seeds] Rumination seeded: #{name}")
    end
  end

  defp seed_email_management do
    name = "Email Management Pipeline"

    if !Repo.exists?(from(r in Rumination, where: r.name == ^name)) do
      {:ok, s1} =
        Ruminations.create_synapse(%{
          name: "Email: Collect",
          description:
            "Read the batch of emails provided. Summarize each one briefly: subject, sender, type (newsletter, personal, transactional, spam, notification), and whether it seems important.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Archivist",
          loop_tools: ["search_email", "read_email"],
          roster: [%{"who" => "all", "preferred_who" => "Collector", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s2} =
        Ruminations.create_synapse(%{
          name: "Email: Classify & Tag",
          description:
            "Classify each email by type. For EACH email, call email_classify with its Thread-ID and category.\n\n" <>
              "Categories: newsletter (marketing, digests), promotion (sales, deals, coupons), spam (junk), " <>
              "personal (real people), transactional (confirmations, resets, receipts, invoices), " <>
              "financial (bank statements, transfers), jobs (applications, recruiters, job alerts), " <>
              "notification (automated alerts, security, account, updates), " <>
              "social (LinkedIn, Twitter), github (PRs, issues, CI), " <>
              "technical (server alerts, DevOps, bugs, incidents, AppSignal).\n\n" <>
              "Use the Thread-ID field from each email header as the thread_id parameter. " <>
              "Process ALL emails in the batch. Do not stop early or ask for clarification.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Triage",
          loop_tools: ["search_email", "email_classify"],
          max_tool_iterations: 60,
          roster: [%{"who" => "all", "preferred_who" => "Classifier", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s3} =
        Ruminations.create_synapse(%{
          name: "Email: Filter Junk",
          description:
            "Review the classified emails. For obvious spam/junk, use email_move to move to the Spam folder. " <>
              "Be conservative — only move obvious junk. When in doubt, leave it.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Triage",
          loop_tools: ["email_tag", "email_move"],
          roster: [%{"who" => "all", "preferred_who" => "Router", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s4} =
        Ruminations.create_synapse(%{
          name: "Email: Unsubscribe",
          description:
            "For emails tagged as newsletters, use read_email to check for List-Unsubscribe headers. " <>
              "For mailto: links, use send_email. For https: links, use fetch_url to visit the unsubscribe page. " <>
              "Tag processed newsletters with +unsubscribed. Report what was found and what action was taken.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Research",
          loop_tools: ["search_email", "read_email", "send_email", "fetch_url", "email_tag"],
          dangerous_tool_mode: "intercept",
          roster: [%{"who" => "all", "preferred_who" => "Gatherer", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, s5} =
        Ruminations.create_synapse(%{
          name: "Email: Summary",
          description:
            "Review all actions taken across the pipeline. Produce a final summary signal: how many emails processed, how many tagged, how many marked as junk, how many unsubscribe attempts.",
          trigger: "manual",
          output_type: "signal",
          cluster_name: "Devil's Advocate",
          loop_tools: ["search_email", "email_tag"],
          roster: [%{"who" => "all", "preferred_who" => "Critic", "how" => "solo", "when" => "sequential"}]
        })

      # Wire to email sense if it exists
      email_sense = Repo.one(from(s in Sense, where: s.source_type == "email"))
      source_ids = if email_sense, do: [to_string(email_sense.id)], else: []

      {:ok, _} =
        Ruminations.create_rumination(%{
          name: name,
          description: "Process email batch: classify, tag, filter junk, unsubscribe from newsletters, produce summary.",
          trigger: if(email_sense, do: "source", else: "manual"),
          source_ids: source_ids,
          status: "paused",
          steps: [
            %{"step_id" => s1.id, "order" => 1},
            %{"step_id" => s2.id, "order" => 2},
            %{"step_id" => s3.id, "order" => 3},
            %{"step_id" => s4.id, "order" => 4},
            %{"step_id" => s5.id, "order" => 5}
          ]
        })

      Logger.info("[Seeds] Rumination seeded: #{name}")
    end
  end

  defp seed_email_backlog_cleanup do
    name = "Email Backlog Cleanup"

    if !Repo.exists?(from(r in Rumination, where: r.name == ^name)) do
      {:ok, step} =
        Ruminations.create_synapse(%{
          name: "Bulk: Classify & File",
          description:
            "You are an email classifier. For EACH email, call email_classify with its Thread-ID and category.\n\n" <>
              "Use the Thread-ID field from each email header as the thread_id parameter.\n\n" <>
              "Process ALL emails in the batch. Do not stop early or ask for clarification.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Triage",
          loop_tools: ["email_classify"],
          max_tool_iterations: 60,
          dangerous_tool_mode: "execute",
          roster: [%{"who" => "all", "preferred_who" => "Classifier", "how" => "solo", "when" => "sequential"}]
        })

      # Wire to email sense if it exists
      email_sense = Repo.one(from(s in Sense, where: s.source_type == "email"))
      source_ids = if email_sense, do: [to_string(email_sense.id)], else: []

      {:ok, _} =
        Ruminations.create_rumination(%{
          name: name,
          description: "One-step bulk classifier. Tags each email, then moves to the appropriate Maildir folder.",
          trigger: if(email_sense, do: "source", else: "manual"),
          source_ids: source_ids,
          status: "paused",
          steps: [%{"step_id" => step.id, "order" => 1}]
        })

      Logger.info("[Seeds] Rumination seeded: #{name}")
    end
  end

  # ---------------------------------------------------------------------------
  # Engrams
  # ---------------------------------------------------------------------------

  defp seed_email_yearly_archive do
    name = "Email Yearly Archive"

    if !Repo.exists?(from(r in Rumination, where: r.name == ^name)) do
      {:ok, step} =
        Ruminations.create_synapse(%{
          name: "Archive Previous Year",
          description:
            "Archive all emails from the previous year. Call email_archive_year with the previous year number. Files go to ZZZ_Archive_YYYY/.",
          trigger: "manual",
          output_type: "freeform",
          cluster_name: "Triage",
          loop_tools: ["email_archive_year"],
          max_tool_iterations: 5,
          dangerous_tool_mode: "execute",
          roster: [%{"who" => "all", "preferred_who" => "Classifier", "how" => "solo", "when" => "sequential"}]
        })

      {:ok, _} =
        Ruminations.create_rumination(%{
          name: name,
          description: "Runs Feb 1 at midnight. Moves all emails from the previous year into ZZZ_Archive_YYYY/.",
          trigger: "scheduled",
          schedule: "0 0 1 2 *",
          status: "active",
          steps: [%{"step_id" => step.id, "order" => 1}]
        })

      Logger.info("[Seeds] Rumination seeded: #{name}")
    end
  end

  defp seed_engrams do
    engrams = [
      # Semantic
      %{
        title: "ExCortex Cluster Map",
        category: "semantic",
        tags: ["clusters", "architecture", "routing"],
        importance: 5,
        source: "manual",
        impression:
          "ExCortex has 14 specialized clusters that route work by domain — Research, Writing, Ops/Infra, Triage, Memory Curator, Daily Briefing, Learning, Creative, Devil's Advocate, Sentinel, Translator, Archivist, Therapist, and the Dev Team.",
        recall: """
        ExCortex organizes agents into 14 clusters, each owning a distinct domain:

        - **Research** — Gather, cross-reference, and synthesize information from URLs, feeds, and documents.
        - **Writing** — Draft, edit, and tone-check prose for internal and external audiences.
        - **Ops/Infra** — Monitor system health, run dependency audits, verify deploy readiness.
        - **Triage** — Classify incoming signals by type and priority, then route to the right cluster.
        - **Memory Curator** — Scan engrams for duplicates, gaps, and staleness; consolidate and promote.
        - **Daily Briefing** — Aggregate overnight signals into a concise morning summary.
        - **Learning** — Extract concepts and relationships from articles, papers, and videos.
        - **Creative** — Generate novel ideas through divergent thinking and lateral association.
        - **Devil's Advocate** — Stress-test proposals by finding flaws and hidden assumptions.
        - **Sentinel** — Watch for slow-burn problems: stale PRs, overdue TODOs, silent failures.
        - **Translator** — Convert content between registers and formats while preserving meaning.
        - **Archivist** — Package engram collections into publishable, self-contained artifacts.
        - **Therapist** — Analyze tone, sentiment, and social signals in communications.
        - **Dev Team** — Self-improvement pipeline: code analysis, writing, review, QA, and merge decisions.
        """,
        body: """
        # ExCortex Cluster Map

        ## Routing Guidance

        When routing work, pick the most specialized cluster. If multiple clusters could handle
        a task, prefer the one whose description most closely matches the core activity.

        ### Research
        Use for: URL fetching, document analysis, multi-source synthesis, fact-checking.
        Neurons: Gatherer (apprentice), Research Analyst (journeyman), Summarizer (journeyman).

        ### Writing
        Use for: Drafting prose, editing, tone adjustment, content creation.
        Neurons: Drafter (journeyman), Editor (journeyman), Tone Checker (apprentice).

        ### Ops/Infra
        Use for: System health checks, dependency audits, configuration review, deploy readiness.
        Neurons: Monitor (apprentice), Auditor (journeyman).

        ### Triage
        Use for: Classifying and routing incoming signals from senses.
        Neurons: Classifier (apprentice), Router (apprentice).

        ### Memory Curator
        Use for: Engram maintenance — deduplication, retagging, promotion, archival.
        Neurons: Curator Scanner (journeyman), Consolidator (journeyman).

        ### Daily Briefing
        Use for: Morning summaries aggregating overnight signals.
        Neurons: Briefing Aggregator (apprentice), Briefing Editor (journeyman).

        ### Learning
        Use for: Knowledge extraction from educational content, concept mapping.
        Neurons: Extractor (journeyman), Knowledge Connector (journeyman).

        ### Creative
        Use for: Brainstorming, divergent thinking, idea generation and refinement.
        Neurons: Diverger (journeyman), Idea Connector (journeyman).

        ### Devil's Advocate
        Use for: Proposal stress-testing, risk assessment, balanced evaluation.
        Neurons: Critic (journeyman), Steelman (journeyman).

        ### Sentinel
        Use for: Periodic sweeps for stale PRs, overdue TODOs, silent failures, error trends.
        Neurons: Watcher (apprentice), Alerter (journeyman).

        ### Translator
        Use for: Converting content between technical/business/casual registers, format conversion.
        Neurons: Translator (journeyman), Formatter (apprentice).

        ### Archivist
        Use for: Collecting and packaging engrams into publishable artifacts.
        Neurons: Collector (apprentice), Packager (journeyman).

        ### Therapist
        Use for: Sentiment analysis, tone detection, communication coaching.
        Neurons: Sensor (apprentice), Advisor (journeyman).

        ### Dev Team
        Use for: Self-improvement — code analysis, implementation, review, QA, UX, merge decisions.
        Managed by the Neuroplasticity pipeline. Not directly routable for general tasks.
        """
      },
      %{
        title: "Memory Tier System",
        category: "semantic",
        tags: ["memory", "engrams", "tiers"],
        importance: 5,
        source: "manual",
        impression:
          "Engrams have three tiers — L0 impression (one sentence), L1 recall (paragraph summary), and L2 body (full content) — loaded progressively to save context window space.",
        recall: """
        The ExCortex memory system stores knowledge as engrams with three tiers of detail:

        - **L0 Impression** — A single sentence capturing the essential point. Always loaded in search results. Should be self-contained enough to decide if deeper loading is needed.
        - **L1 Recall** — A paragraph-length summary with key details. Loaded on demand via `Memory.load_recall/1`. Good for most agent tasks.
        - **L2 Body** — The full content with all detail and context. Loaded via `Memory.load_deep/1`. Used when the agent needs complete information.

        Categories: `semantic` (facts/knowledge), `episodic` (events/experiences), `procedural` (how-to/processes).
        Importance: 1 (low) to 5 (critical). Higher importance engrams surface first in queries.
        Tags: Free-form strings used for querying. Use consistent, lowercase tags.

        The `Memory.query/2` function returns L0 impressions by default. Agents should scan impressions first, then load recall/body only for relevant engrams. This progressive loading keeps context windows efficient.
        """,
        body: """
        # Memory Tier System

        ## Overview

        ExCortex stores knowledge as **engrams** — structured memory units with progressive detail levels.
        This tiered approach balances comprehensive storage with efficient retrieval.

        ## Tiers

        ### L0 — Impression
        - One sentence, ~20 words
        - Always returned in search results
        - Purpose: Let agents quickly scan relevance without loading full content
        - Example: "ExCortex uses 14 clusters to route work by domain, each with specialized neurons."

        ### L1 — Recall
        - One to three paragraphs
        - Loaded on demand via `Memory.load_recall/1`
        - Purpose: Provide enough detail for most agent tasks
        - Should include key facts, names, numbers — everything except raw data

        ### L2 — Body
        - Full content, no length limit
        - Loaded via `Memory.load_deep/1`
        - Purpose: Complete reference when agents need every detail
        - May include code samples, full lists, raw data, extended explanations

        ## Categories

        - **semantic** — Facts, definitions, knowledge about the world or system
        - **episodic** — Events, experiences, things that happened at a specific time
        - **procedural** — How-to guides, processes, step-by-step instructions

        ## Writing Good Engrams

        1. **Impression first** — Write the L0 before anything else. If you can't summarize it in one sentence, the engram might be too broad.
        2. **Tags matter** — Use 2-5 lowercase tags. Include the domain, the type, and one or two specific terms.
        3. **Importance honestly** — 5 = critical system knowledge, 4 = important reference, 3 = useful context, 2 = nice to have, 1 = ephemeral note.
        4. **Source tracking** — Always set `source` to indicate origin: manual, rumination, extraction, muse, wonder.
        5. **Progressive detail** — Each tier should add value. Don't repeat L0 content verbatim in L1.

        ## Querying

        ```elixir
        # Search by tags — returns L0 impressions
        Memory.query(%{"tags" => ["clusters", "architecture"]})

        # Load more detail
        Memory.load_recall(engram_id)
        Memory.load_deep(engram_id)
        ```

        ## Automatic Extraction

        The `Memory.Extractor` module automatically creates episodic engrams from completed daydreams.
        The `Memory.TierGenerator` then asynchronously generates L0/L1 summaries via LLM for engrams
        that were created without them.
        """
      },
      %{
        title: "Signal Types Guide",
        category: "semantic",
        tags: ["signals", "dashboard", "types"],
        importance: 4,
        source: "manual",
        impression:
          "Signals are dashboard cards with types like note, briefing, alert, action_list, checklist, metric, and more — each rendered differently on the cortex.",
        recall: """
        Signals are the primary output mechanism for the cortex dashboard. Each signal has a type that determines how it renders:

        - **note** — Simple text card for general information or quick thoughts.
        - **briefing** — Structured summary, typically multi-section with headers. Used by Daily Briefing.
        - **alert** — Urgent notification with severity indicator. Used by Sentinel for problems.
        - **action_list** — Ordered list of action items with done/not-done tracking. Stored in metadata as `%{"items" => [%{"text" => "...", "done" => false}]}`.
        - **checklist** — Similar to action_list but for verification/review checklists.
        - **metric** — Numeric dashboard card showing a value, trend, or comparison.
        - **proposal** — Structured proposal for review, often paired with Devil's Review.
        - **freeform** — Unstructured content, rendered as markdown.
        - **link** — External link card with title, URL, and optional description.
        - **table** — Tabular data rendered as a formatted table.
        - **media** — Image, video, or audio content card.
        - **augury** — Prediction or forecast card with confidence level.
        - **meeting** — Meeting notes or agenda card.

        Signals can be pinned (shown at top), tagged for filtering, and associated with a cluster or rumination.
        """,
        body: """
        # Signal Types Guide

        ## Overview

        Signals are dashboard cards displayed on the cortex (/cortex). They are the primary way
        ruminations, senses, and agents communicate results to the user.

        ## Types

        ### note
        Simple text card. Use for quick observations, reminders, or general information.
        Body is rendered as markdown.

        ### briefing
        Multi-section structured summary. Typically produced by the Daily Briefing rumination.
        Should have clear headers, bullet points, and action tags ([ACTION], [FYI], [WATCH]).

        ### alert
        Urgent notification. Used by Sentinel sweep and monitoring agents.
        Should include severity level and recommended action.

        ### action_list
        Ordered list of actionable items with completion tracking.
        Metadata format: `%{"items" => [%{"text" => "Do this thing", "done" => false}]}`
        Items can be checked off in the UI.

        ### checklist
        Verification or review checklist. Similar structure to action_list.
        Used for QA, deploy readiness, or review processes.

        ### metric
        Numeric or KPI card. Shows a value with optional trend, comparison, or sparkline.
        Metadata can include: value, unit, trend, previous_value.

        ### proposal
        Structured proposal for human review. Often output by Creative cluster
        or input to Devil's Review rumination.

        ### freeform
        Catch-all for unstructured content. Body rendered as markdown.
        Use when no other type fits.

        ### link
        External link with title, URL, and description. Metadata includes `url`.

        ### table
        Tabular data. Metadata includes `headers` and `rows` arrays.

        ### media
        Image, video, or audio content. Metadata includes `url` and `media_type`.

        ### augury
        Prediction or forecast. Metadata includes `confidence` (0-1) and `timeframe`.

        ### meeting
        Meeting notes or agenda. Body contains the notes, metadata may include
        `attendees`, `date`, and `action_items`.

        ## Attributes

        - **pinned** — Boolean. Pinned signals appear at the top of the dashboard.
        - **source** — String identifying origin: "seed", "rumination", "sense", "manual", etc.
        - **tags** — Array of strings for filtering and search.
        - **cluster_name** — Optional association with a cluster.
        - **rumination_id** — Optional association with the rumination that created it.
        - **status** — "active" (visible), "dismissed" (hidden), "archived" (preserved but hidden).
        - **pin_slug** — Unique slug for pinned signals, enabling stable ordering.
        - **pin_order** — Integer for ordering pinned signals.
        """
      },
      %{
        title: "Sense Types Overview",
        category: "semantic",
        tags: ["senses", "sources", "data"],
        importance: 4,
        source: "manual",
        impression:
          "Senses are data sources that feed the cortex — types include git, feed, email, webhook, cortex, directory, github_issues, nextcloud, and more.",
        recall: """
        Senses are managed data sources that pull external information into the cortex for processing:

        - **cortex** — Self-monitoring: watches ExCortex's own health, logs, and metrics.
        - **github_issues** — Polls a GitHub repo for issues matching a label filter.
        - **directory** — Watches a local filesystem directory for file changes with extension filtering.
        - **feed** — Polls an RSS/Atom feed URL for new entries.
        - **email** — Queries a mailbox (notmuch-style) for new messages.
        - **nextcloud** — Syncs with a Nextcloud instance for document changes.
        - **git** — Watches a git repository for new commits, branches, or tags.
        - **webhook** — Receives push data via `POST /api/webhooks/:sense_id` with optional Bearer auth.
        - **url** — Periodically fetches a URL and detects content changes.
        - **websocket** — Maintains a persistent WebSocket connection for streaming data.
        - **obsidian** — Syncs with an Obsidian vault directory for note changes.
        - **media** — Watches for new media files (images, audio, video).

        Each sense has: config (type-specific settings), status (active/paused/error), polling interval, and state (tracking cursor/last-seen). Senses are managed by a DynamicSupervisor with per-sense worker processes.
        """,
        body: """
        # Sense Types Overview

        ## Architecture

        Senses run as supervised worker processes under a DynamicSupervisor. Each sense:
        1. Polls or listens for new data on its configured interval
        2. Passes incoming data to the Evaluator module
        3. The Evaluator routes data through the Sense Intake rumination (Triage cluster)
        4. Triage classifies and routes to the appropriate cluster

        ## Types

        ### cortex
        Self-monitoring sense. Watches ExCortex's own health metrics, error rates, and system status.
        Config: `%{"interval" => milliseconds}`

        ### github_issues
        Polls GitHub API for issues matching repo and label filters.
        Config: `%{"repo" => "owner/repo", "label" => "bug", "interval" => ms}`

        ### directory
        Watches a local directory for file changes using the `file_system` library.
        Config: `%{"path" => "/path/to/dir", "extensions" => [".ex", ".md"], "interval" => ms}`

        ### feed
        Polls RSS/Atom feeds for new entries using the `req` HTTP client.
        Config: `%{"url" => "https://example.com/feed.xml", "interval" => ms}`

        ### email
        Queries a local mailbox using notmuch-style search queries.
        Config: `%{"query" => "tag:inbox AND tag:unread", "interval" => ms}`

        ### nextcloud
        Syncs with a Nextcloud instance via WebDAV.
        Config: `%{"base_url" => "https://cloud.example.com", "username" => "", "password" => "", "interval" => ms}`

        ### git
        Watches a git repository for new commits, branches, or tags.
        Config: `%{"repo_path" => "/path/to/repo", "branch" => "main", "interval" => ms}`

        ### webhook
        Receives push data. Endpoint: `POST /api/webhooks/:sense_id`
        Optional Bearer token auth configured in the sense config.
        Config: `%{"auth_token" => "optional-secret"}`

        ### url
        Periodically fetches a URL and detects content changes via diffing.
        Config: `%{"url" => "https://example.com/page", "interval" => ms}`

        ### websocket
        Maintains a persistent WebSocket connection using the `fresh` library.
        Config: `%{"url" => "wss://example.com/ws", "reconnect" => true}`

        ### obsidian
        Watches an Obsidian vault directory for note changes.
        Config: `%{"vault_path" => "/path/to/vault", "interval" => ms}`

        ### media
        Watches for new media files in a directory.
        Config: `%{"path" => "/path/to/media", "types" => ["image", "audio", "video"], "interval" => ms}`

        ## Status

        - **active** — Worker is running and polling/listening
        - **paused** — Worker is stopped, will not poll until activated
        - **error** — Worker encountered an error, `error_message` field has details

        ## Reflexes

        Reflexes are sense templates (blueprints) defined in `ExCortex.Senses.Reflex`.
        They provide pre-configured sense setups that users can instantiate with their own
        credentials and paths.
        """
      },
      # Procedural
      %{
        title: "Writing Effective Synapse Rosters",
        category: "procedural",
        tags: ["synapses", "rosters", "configuration"],
        importance: 4,
        source: "manual",
        impression:
          "Synapse rosters define which neurons participate in a pipeline step — specify who, preferred_who, how (solo/panel/consensus), and when (sequential/parallel).",
        recall: """
        A synapse roster is a list of role assignments that control how a pipeline step executes:

        Each roster entry is a map with:
        - **who** — "all" (any neuron in the cluster) or a specific neuron name.
        - **preferred_who** — Hint for which neuron to prefer. Used when `who` is "all".
        - **how** — Execution mode: "solo" (one neuron), "panel" (multiple neurons discuss), "consensus" (multiple neurons must agree).
        - **when** — Timing: "sequential" (one after another) or "parallel" (all at once).

        Common patterns:
        - Single expert: `[%{"who" => "all", "preferred_who" => "Research Analyst", "how" => "solo", "when" => "sequential"}]`
        - Panel review: `[%{"who" => "all", "how" => "panel", "when" => "parallel"}]` — all cluster neurons weigh in
        - Consensus gate: `[%{"who" => "all", "how" => "consensus", "when" => "parallel"}]` — must agree to proceed

        The cluster_name on the synapse determines which neurons are available. Roster entries that reference neurons not in that cluster will be skipped.
        """,
        body: """
        # Writing Effective Synapse Rosters

        ## Roster Structure

        Each synapse has a `roster` field — a list of maps defining participation:

        ```json
        [
          {"who": "all", "preferred_who": "Gatherer", "how": "solo", "when": "sequential"}
        ]
        ```

        ## Fields

        ### who
        - `"all"` — Any neuron in the synapse's cluster can fill this role
        - `"Specific Name"` — Only the named neuron is eligible

        ### preferred_who
        - Optional hint when `who` is "all"
        - The system will prefer this neuron if available and not busy
        - Falls back to any available neuron in the cluster

        ### how
        - `"solo"` — One neuron handles the entire step alone
        - `"panel"` — Multiple neurons each produce output; results are collected
        - `"consensus"` — Multiple neurons must reach agreement; disagreement triggers escalation

        ### when
        - `"sequential"` — Roster entries execute one after another, each seeing previous output
        - `"parallel"` — All roster entries execute simultaneously

        ## Common Patterns

        ### Simple Expert Task
        One neuron does the work. Most common pattern.
        ```json
        [{"who": "all", "preferred_who": "Research Analyst", "how": "solo", "when": "sequential"}]
        ```

        ### Review Panel
        Multiple perspectives on the same input. Good for quality gates.
        ```json
        [
          {"who": "Critic", "how": "solo", "when": "parallel"},
          {"who": "Steelman", "how": "solo", "when": "parallel"}
        ]
        ```

        ### Consensus Gate
        All neurons must agree. Use for high-stakes decisions.
        ```json
        [{"who": "all", "how": "consensus", "when": "parallel"}]
        ```

        ### Sequential Pipeline
        Each neuron builds on the previous output. Good for refinement.
        ```json
        [
          {"who": "all", "preferred_who": "Drafter", "how": "solo", "when": "sequential"},
          {"who": "all", "preferred_who": "Editor", "how": "solo", "when": "sequential"}
        ]
        ```

        ## Tips

        1. **Start with solo** — Most steps work fine with a single neuron. Add complexity only when needed.
        2. **Use preferred_who** — It guides without being rigid. If the preferred neuron is busy, work still proceeds.
        3. **Consensus is expensive** — Each participating neuron makes an LLM call. Use sparingly.
        4. **Match cluster to step** — The synapse's cluster_name determines the neuron pool. Don't put a Research roster on a Writing synapse.
        """
      },
      %{
        title: "Prompt Engineering for Neurons",
        category: "procedural",
        tags: ["prompts", "neurons", "llm"],
        importance: 4,
        source: "manual",
        impression:
          "Effective neuron system prompts are role-focused, include clear guidelines, specify output format, and avoid over-constraining the LLM.",
        recall: """
        Patterns that work well for ExCortex neuron system prompts:

        1. **Identity first** — Start with "You are [Name], responsible for [core job]." This anchors the LLM.
        2. **Guidelines block** — Use a "Guidelines:" section with bullet points for behavioral rules.
        3. **Output format** — Specify expected output structure: markdown sections, bullet lists, verdicts, etc.
        4. **Negative constraints** — State what NOT to do: "Do not self-censor", "Do not pad with filler."
        5. **Scope boundaries** — Be clear about what's in and out of scope for this neuron.
        6. **Tool awareness** — If the neuron has access to tools, mention which ones and when to use them.

        Anti-patterns to avoid:
        - Overly long prompts (>500 words) — the LLM loses focus
        - Contradictory instructions — "be concise" + "be thorough" without guidance on when
        - Vague roles — "You are a helpful assistant" gives no useful anchoring
        - Hardcoded facts — put facts in engrams/axioms, not in prompts
        """,
        body: """
        # Prompt Engineering for Neurons

        ## Structure Template

        ```
        You are [Name], responsible for [one-line job description].
        [Optional: brief context about when/why this neuron is called]

        Guidelines:
        - [Specific behavioral rule 1]
        - [Specific behavioral rule 2]
        - [Output format expectation]
        - [Scope boundary]
        - [Quality bar]
        ```

        ## Principles

        ### Role Anchoring
        The first sentence matters most. "You are Critic, responsible for finding flaws in proposals"
        immediately tells the LLM its perspective, voice, and purpose.

        ### Actionable Guidelines
        Each guideline should be testable. "Write clearly" is vague. "Use active voice and keep
        sentences under 25 words" is actionable.

        ### Output Specification
        Tell the neuron what shape the output should take:
        - "Produce a structured analysis with sections: Key Findings, Evidence Quality, Open Questions"
        - "Output a JSON object with keys: severity, description, recommendation"
        - "Format as a markdown checklist with severity tags"

        ### Progressive Disclosure
        For complex tasks, list steps in order:
        1. First, scan for X
        2. Then, evaluate Y
        3. Finally, produce Z

        ### Negative Constraints
        Explicitly state what to avoid:
        - "Do not include disclaimers about being an AI"
        - "Do not repeat the input back before analyzing it"
        - "Skip preamble — start directly with findings"

        ## Model-Specific Notes

        ### Apprentice Neurons (ministral-3:8b)
        - Keep prompts shorter (<200 words)
        - Simpler output formats (flat lists over nested structures)
        - More explicit step-by-step instructions
        - Avoid asking for nuanced judgment

        ### Journeyman Neurons (devstral-small-2:24b)
        - Can handle longer, more nuanced prompts
        - Good at structured output and tool calling
        - Can balance competing concerns
        - Reliable at following multi-step instructions

        ### Claude Neurons (claude_haiku, claude_sonnet, claude_opus)
        - Excellent at nuanced judgment and complex reasoning
        - Can handle long context and detailed instructions
        - Good at self-correction when prompted
        - More expensive — use for high-value tasks

        ## Anti-Patterns

        1. **The Essay Prompt** — 1000+ words of instructions. The model drowns in context.
        2. **The Contradictory Prompt** — "Be thorough AND concise" without guidance on trade-offs.
        3. **The Generic Prompt** — "You are a helpful assistant." Provides no useful anchoring.
        4. **The Fact-Stuffed Prompt** — Embedding reference data in prompts instead of using axioms/engrams.
        5. **The Rigid Template** — Over-specifying output format kills the model's ability to adapt to edge cases.
        """
      },
      %{
        title: "When to Escalate",
        category: "procedural",
        tags: ["escalation", "verdicts", "pipeline"],
        importance: 3,
        source: "manual",
        impression:
          "Escalate when confidence is low, when a consensus step disagrees, or when a verdict synapse returns reject — thresholds are configurable per rumination.",
        recall: """
        Escalation in ExCortex ruminations is triggered by three mechanisms:

        1. **Verdict rejection** — A synapse with output_type "verdict" returns a negative verdict. The rumination can be configured to halt, retry, or escalate to a different cluster.

        2. **Consensus failure** — A synapse with "how": "consensus" in the roster fails to reach agreement. When neurons disagree, the step is flagged for review.

        3. **Low confidence** — An agent explicitly signals low confidence in its output. Other agents in the pipeline should watch for hedging language and uncertainty markers.

        Escalation actions:
        - **Halt** — Stop the daydream and flag for human review
        - **Retry** — Re-run the step with different parameters or a different neuron
        - **Reroute** — Send to a different cluster (e.g., Triage to Devil's Advocate)
        - **Flag** — Continue but attach a warning to the output signal

        The Neuroplasticity pipeline uses verdict-based routing: PM Triage decides if an issue is worth fixing, Code Reviewer decides if the implementation is acceptable, and PM Merge decides whether to merge.
        """,
        body: """
        # When to Escalate

        ## Escalation Triggers

        ### Verdict-Based Routing
        Synapses with `output_type: "verdict"` produce explicit go/no-go decisions.
        When a verdict is negative, the rumination's step configuration determines what happens next.

        The Neuroplasticity pipeline is the canonical example:
        - PM Triage → verdict: proceed or skip
        - Code Reviewer → verdict: approve, request changes, or reject
        - PM Merge → verdict: merge, revise, or abandon

        ### Consensus Failure
        When a synapse uses `"how": "consensus"` in its roster, all participating neurons
        must agree. Disagreement triggers escalation.

        Common patterns:
        - 2 of 3 agree → proceed with minority dissent noted
        - No majority → halt and flag for human review
        - All disagree → reroute to Devil's Advocate cluster for structured debate

        ### Confidence Signals
        Agents can self-report low confidence. Watch for:
        - Explicit: "I'm not confident about this" or "Low confidence"
        - Implicit: Excessive hedging, many caveats, contradictory recommendations
        - Missing data: "I couldn't find information about X"

        ## Escalation Actions

        ### Halt
        Stop the daydream immediately. Create a signal flagging the issue.
        Use when: The problem is fundamental and continuing would waste resources.

        ### Retry
        Re-run the step with:
        - A different neuron from the same cluster
        - A more capable model (escalate from apprentice to journeyman)
        - Additional context loaded from memory

        ### Reroute
        Send the work to a different cluster entirely.
        Use when: The current cluster lacks the expertise needed.
        Example: Research discovers a security issue → reroute to Ops/Infra.

        ### Flag and Continue
        Attach a warning to the output but don't stop the pipeline.
        Use when: The concern is notable but not blocking.

        ## Configuration

        Escalation behavior is configured per synapse in the rumination's step configuration.
        The `output_type` field determines what verdicts are possible:
        - `"freeform"` — No escalation triggers (output is just text)
        - `"verdict"` — Explicit go/no-go with escalation on rejection
        - `"signal"` — Produces a dashboard signal card
        - `"artifact"` — Produces an engram for memory storage
        """
      },
      %{
        title: "Memory Extraction Patterns",
        category: "procedural",
        tags: ["memory", "extraction", "tagging"],
        importance: 3,
        source: "manual",
        impression:
          "Tag engrams with 2-5 lowercase terms covering domain, type, and specifics — consistent tagging is the single biggest factor in memory retrieval quality.",
        recall: """
        Good memory extraction and tagging patterns for ExCortex engrams:

        **Tagging rules:**
        - Use 2-5 tags per engram. Fewer is better than too many.
        - Lowercase, singular form: "cluster" not "Clusters"
        - Include: one domain tag, one type tag, one or two specific tags
        - Domain tags: architecture, memory, signal, sense, neuron, cluster, rumination, pipeline
        - Type tags: guide, reference, pattern, example, log, decision, incident

        **Extraction timing:**
        - After every completed daydream (automatic via Memory.Extractor)
        - After Muse sessions that produce useful insights (manual or prompted)
        - When agents discover reusable knowledge during any task

        **Quality checks:**
        - Does the title clearly indicate what this engram is about?
        - Is the impression self-contained enough to decide if loading more is worthwhile?
        - Are the tags consistent with existing engrams on the same topic?
        - Is the importance rating honest (not everything is a 5)?
        """,
        body: """
        # Memory Extraction Patterns

        ## Tagging Guide

        ### Structure
        Every engram should have 2-5 tags following this pattern:
        1. **Domain tag** — What area of the system: architecture, memory, signal, sense, neuron, cluster, rumination, pipeline, llm, tool
        2. **Type tag** — What kind of knowledge: guide, reference, pattern, example, log, decision, incident, config
        3. **Specific tags** — 1-2 terms specific to this engram's content

        ### Examples
        - Engram about cluster routing: `["cluster", "guide", "routing"]`
        - Engram about a production incident: `["ops", "incident", "database"]`
        - Engram about a useful prompt pattern: `["llm", "pattern", "prompt"]`

        ### Anti-Patterns
        - Too many tags: `["system", "architecture", "design", "overview", "guide", "reference", "important"]` — pick 3
        - Too vague: `["info", "data"]` — these match everything and help nothing
        - Inconsistent: "clusters" on one engram and "cluster" on another — pick one form

        ## Extraction Timing

        ### Automatic (Memory.Extractor)
        After every completed daydream, the Extractor module:
        1. Reads the daydream's output
        2. Creates an episodic engram with the daydream context
        3. Queues L0/L1 generation via TierGenerator

        ### Manual Extraction
        Agents should create engrams when they discover:
        - Reusable knowledge not already in memory
        - Important decisions and their rationale
        - Patterns that worked (or failed) for future reference
        - Corrections to existing knowledge

        ### From Muse Sessions
        When a Muse (RAG) session produces a useful synthesis:
        - Save the key insight as a semantic engram
        - Link it to the engrams that were queried during the session
        - Use recall paths to track provenance

        ## Quality Checklist

        Before creating an engram, verify:
        - [ ] Title is descriptive and unique (not "Notes" or "Research")
        - [ ] Impression is one sentence and self-contained
        - [ ] Tags follow the domain/type/specific pattern
        - [ ] Importance is honestly rated (1-5)
        - [ ] Category is correct (semantic/episodic/procedural)
        - [ ] Not a duplicate of an existing engram (search first!)

        ## Importance Scale

        - **5** — Critical system knowledge. Loss would cause errors or confusion.
        - **4** — Important reference. Frequently needed by agents.
        - **3** — Useful context. Occasionally relevant.
        - **2** — Nice to have. Background information.
        - **1** — Ephemeral. May be cleaned up in maintenance.
        """
      },
      # Episodic
      %{
        title: "Seed Bootstrap",
        category: "episodic",
        tags: ["seed", "bootstrap", "system"],
        importance: 2,
        source: "manual",
        impression:
          "ExCortex was bootstrapped with seed data: 14 clusters, ~26 neurons, 6 ruminations, 9 engrams, 1 axiom, 3 signals, and 6 senses.",
        recall: """
        The ExCortex system was initialized with seed data to provide a working starting point:

        - **14 clusters** — Research, Writing, Ops/Infra, Triage, Memory Curator, Daily Briefing, Learning, Creative, Devil's Advocate, Sentinel, Translator, Archivist, Therapist, plus Dev Team (seeded by Neuroplasticity).
        - **~26 neurons** — 2-3 per cluster with apprentice and journeyman ranks.
        - **6 ruminations** — Morning Briefing, Sense Intake, Research Digest, Memory Maintenance, Sentinel Sweep, Devil's Review.
        - **9 engrams** — System knowledge covering clusters, memory tiers, signals, senses, and procedures.
        - **1 axiom** — Comprehensive system reference document for agent use.
        - **3 signals** — Welcome note, system status briefing, and onboarding action list.
        - **6 senses** — Self-monitor (active), plus paused templates for GitHub issues, directory watch, RSS feed, email, and Nextcloud.

        This seed data is idempotent — running seeds again will not create duplicates.
        """,
        body: """
        # Seed Bootstrap Record

        ## When
        System initialization via `ExCortex.Seeds.seed/0`.

        ## What Was Created

        ### Clusters (14)
        Research, Writing, Ops/Infra, Triage, Memory Curator, Daily Briefing,
        Learning, Creative, Devil's Advocate, Sentinel, Translator, Archivist, Therapist.
        (Dev Team is seeded separately by the Neuroplasticity system.)

        ### Neurons (~26)
        Each cluster received 2-3 neurons with role-specific system prompts:
        - Apprentice neurons use ministral-3:8b (fast, cheaper)
        - Journeyman neurons use devstral-small-2:24b (reliable tool-calling)

        ### Ruminations (6)
        - Morning Briefing — Scheduled 7am daily (paused)
        - Sense Intake — Triggered by source data (active)
        - Research Digest — Manual trigger (paused)
        - Memory Maintenance — Scheduled weekly Sunday 3am (paused)
        - Sentinel Sweep — Scheduled 8am daily (paused)
        - Devil's Review — Manual trigger (paused)

        ### Engrams (9)
        - 4 semantic: Cluster Map, Memory Tiers, Signal Types, Sense Types
        - 4 procedural: Synapse Rosters, Prompt Engineering, Escalation, Memory Extraction
        - 1 episodic: This bootstrap record

        ### Axiom (1)
        - ex_cortex_system_reference: Comprehensive markdown reference for agents

        ### Signals (3)
        - Welcome to ExCortex (note, pinned)
        - System Status (briefing, pinned)
        - Try This First (action_list, pinned)

        ### Senses (6)
        - Self-Monitor (cortex, active)
        - ExCortex Repo (github_issues, paused)
        - Project Watch (directory, paused)
        - RSS Feed (feed, paused)
        - Email Inbox (email, paused)
        - Nextcloud (nextcloud, paused)

        ## Idempotency
        All seed functions check for existing records before inserting.
        Running seeds multiple times is safe and will not create duplicates.
        """
      }
    ]

    for engram_attrs <- engrams do
      title = engram_attrs.title

      if Repo.exists?(from(e in Engram, where: e.title == ^title)) do
        Logger.info("[Seeds] Engram already exists: #{title}")
      else
        case Memory.create_engram(engram_attrs) do
          {:ok, _} -> Logger.info("[Seeds] Engram seeded: #{title}")
          {:error, cs} -> Logger.warning("[Seeds] Engram #{title} failed: #{inspect(cs.errors)}")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Axioms
  # ---------------------------------------------------------------------------

  defp seed_axioms do
    if Lexicon.get_axiom_by_name("ex_cortex_system_reference") do
      Logger.info("[Seeds] Axiom already exists: ex_cortex_system_reference")
    else
      attrs = %{
        name: "ex_cortex_system_reference",
        description: "Comprehensive system reference for ExCortex agents — vocabulary, architecture, tools, conventions.",
        content_type: "markdown",
        tags: ["system", "reference", "architecture"],
        content: """
        # ExCortex System Reference

        > This document is the primary reference for all ExCortex agents (neurons).
        > Query it via the `query_axiom` tool when you need system information.

        ---

        ## 1. Vocabulary

        ExCortex uses a brain/consciousness metaphor throughout. Learn these terms:

        | Term | Meaning |
        |------|---------|
        | **Cluster** | A team of agents organized around a domain (e.g., Research, Writing) |
        | **Neuron** | An individual agent/role within a cluster |
        | **Pathway** | The definition/charter of a cluster — what it does and how |
        | **Rumination** | A multi-step pipeline that orchestrates work across neurons |
        | **Daydream** | A single execution (run) of a Rumination |
        | **Synapse** | One step within a Rumination pipeline |
        | **Impulse** | A single execution (run) of a Synapse step |
        | **Engram** | A memory unit — stored knowledge with tiered detail levels |
        | **Signal** | A dashboard card — the primary output/notification mechanism |
        | **Sense** | A data source that feeds information into the cortex |
        | **Reflex** | A template/blueprint for creating a Sense |
        | **Expression** | A notification channel (email, webhook, etc.) |
        | **Axiom** | A reference dataset in the Lexicon (like this document) |
        | **Thought** | A saved single-step query template |
        | **Cortex** | The main dashboard — central hub of the system |
        | **Instinct** | Settings and configuration |
        | **Muse** | The RAG engine — data-grounded chat over engrams and axioms |
        | **Wonder** | Ephemeral LLM chat without data grounding |

        ---

        ## 2. Architecture Flow

        ```
        Senses (data in) → Triage Cluster → Route to appropriate Cluster
                                                    ↓
                                              Rumination triggered
                                                    ↓
                                          Synapse 1 → Synapse 2 → Synapse N
                                          (Impulse)   (Impulse)   (Impulse)
                                                    ↓
                                          Output: Signal / Engram / Verdict
        ```

        ### Data Flow
        1. **Senses** poll or receive external data (feeds, files, webhooks, etc.)
        2. **Triage cluster** classifies and routes incoming data
        3. **Ruminations** orchestrate multi-step processing
        4. Each **Synapse** step runs one or more **Neurons** (creating **Impulses**)
        5. Output becomes **Signals** (dashboard cards) or **Engrams** (memory)

        ### Execution Model
        - Each Synapse has a **roster** defining which neurons participate
        - Roster modes: solo (one neuron), panel (multiple), consensus (must agree)
        - Timing: sequential (one after another) or parallel (all at once)
        - A Synapse's `output_type` determines what it produces: freeform, verdict, signal, artifact

        ---

        ## 3. Clusters and Routing

        ### Research
        **Domain:** Information gathering, synthesis, and analysis
        **Neurons:** Gatherer, Research Analyst, Summarizer
        **Route here when:** You need to fetch, cross-reference, or distill information from sources

        ### Writing
        **Domain:** Content creation, editing, and tone adjustment
        **Neurons:** Drafter, Editor, Tone Checker
        **Route here when:** You need prose written, revised, or adapted for an audience

        ### Ops/Infra
        **Domain:** System health, dependencies, and deployment
        **Neurons:** Monitor, Auditor
        **Route here when:** System health checks, dependency audits, or config review needed

        ### Triage
        **Domain:** Classification and routing of incoming signals
        **Neurons:** Classifier, Router
        **Route here when:** New data arrives from a Sense and needs classification

        ### Memory Curator
        **Domain:** Engram maintenance and knowledge base quality
        **Neurons:** Curator Scanner, Consolidator
        **Route here when:** Memory needs deduplication, retagging, promotion, or cleanup

        ### Daily Briefing
        **Domain:** Morning summary aggregation
        **Neurons:** Briefing Aggregator, Briefing Editor
        **Route here when:** Producing a daily digest of overnight signals

        ### Learning
        **Domain:** Knowledge extraction and concept mapping
        **Neurons:** Extractor, Knowledge Connector
        **Route here when:** Educational content needs to be processed into engrams

        ### Creative
        **Domain:** Idea generation and refinement
        **Neurons:** Diverger, Idea Connector
        **Route here when:** Brainstorming, divergent thinking, or novel combinations needed

        ### Devil's Advocate
        **Domain:** Proposal stress-testing and risk assessment
        **Neurons:** Critic, Steelman
        **Route here when:** A plan or proposal needs adversarial review

        ### Sentinel
        **Domain:** Slow-burn problem detection
        **Neurons:** Watcher, Alerter
        **Route here when:** Periodic sweeps for stale PRs, TODOs, silent failures

        ### Translator
        **Domain:** Content adaptation between contexts and formats
        **Neurons:** Translator, Formatter
        **Route here when:** Content needs register shift or format conversion

        ### Archivist
        **Domain:** Knowledge packaging and publishing
        **Neurons:** Collector, Packager
        **Route here when:** Engrams need to be compiled into publishable artifacts

        ### Therapist
        **Domain:** Sentiment analysis and communication coaching
        **Neurons:** Sensor, Advisor
        **Route here when:** Text needs tone analysis or response suggestions

        ### Dev Team
        **Domain:** Self-improvement (Neuroplasticity pipeline)
        **Not directly routable** — triggered by GitHub issues labeled `self-improvement`
        **Pipeline:** PM Triage → Code Writer → Code Reviewer → QA → UX Designer → PM Merge

        ---

        ## 4. Available Tools

        Agents may have access to these tools depending on their role:

        ### Sandbox Commands (run_sandbox)
        Only these commands are allowed in the sandbox:
        - `mix test [file] [--only tag]` — Run tests
        - `mix credo [--all]` — Static analysis
        - `mix excessibility` — Accessibility audit
        - `mix format [--check-formatted]` — Code formatting
        - `mix dialyzer` — Type checking
        - `mix deps.audit` — Dependency audit

        **Important:** No other shell commands work in the sandbox. Do not attempt `cd`, `ls`, `cat`, etc.

        ### Memory Tools
        - `query_memory` — Search engrams by tags. Returns L0 impressions. Always query before creating.
        - `query_axiom` — Search axioms (reference documents like this one).

        ### GitHub Tools
        - `create_github_issue` — File a new issue
        - `search_github` — Search issues and PRs
        - `open_pr` — Create a pull request
        - `merge_pr` — Merge a pull request

        ### File Tools
        - `read_file` — Read file contents
        - `write_file` — Create or overwrite a file
        - `edit_file` — Make targeted edits to a file
        - `list_files` — List directory contents

        ### Git Tools
        - `git_commit` — Create a commit
        - `git_push` — Push to remote
        - `setup_worktree` — Create a git worktree for isolated changes

        ---

        ## 5. Memory System

        ### Tiers
        - **L0 Impression** — One sentence. Always loaded in search results.
        - **L1 Recall** — Paragraph summary. Loaded via `Memory.load_recall/1`.
        - **L2 Body** — Full content. Loaded via `Memory.load_deep/1`.

        ### Categories
        - `semantic` — Facts and knowledge
        - `episodic` — Events and experiences
        - `procedural` — How-to and processes

        ### Importance (1-5)
        5 = critical, 4 = important, 3 = useful, 2 = nice to have, 1 = ephemeral

        ### Best Practices
        - Always `query_memory` before creating new engrams to avoid duplicates
        - Use 2-5 lowercase tags: domain + type + specifics
        - Write the impression first — if you can't summarize in one sentence, split the engram
        - Automatic extraction happens after completed daydreams via Memory.Extractor

        ---

        ## 6. Signal Types

        | Type | Use For |
        |------|---------|
        | `note` | Quick observations, reminders |
        | `briefing` | Structured summaries with sections |
        | `alert` | Urgent notifications with severity |
        | `action_list` | Ordered items with done/not-done tracking |
        | `checklist` | Verification/review lists |
        | `metric` | Numeric KPIs with trends |
        | `proposal` | Plans for review |
        | `freeform` | Unstructured markdown content |
        | `link` | External URLs with descriptions |
        | `table` | Tabular data |
        | `media` | Images, video, audio |
        | `augury` | Predictions with confidence levels |
        | `meeting` | Meeting notes and agendas |

        ---

        ## 7. Sense Types

        | Type | Mechanism |
        |------|-----------|
        | `cortex` | Self-monitoring (system health) |
        | `github_issues` | Poll GitHub API for issues |
        | `directory` | Watch filesystem for changes |
        | `feed` | Poll RSS/Atom feeds |
        | `email` | Query local mailbox |
        | `nextcloud` | Sync via WebDAV |
        | `git` | Watch repo for commits |
        | `webhook` | Receive POST to /api/webhooks/:id |
        | `url` | Fetch URL and detect changes |
        | `websocket` | Persistent streaming connection |
        | `obsidian` | Watch Obsidian vault |
        | `media` | Watch for new media files |

        ---

        ## 8. Key Conventions

        ### Config Priority
        Settings DB (Instinct UI) → Application env → env vars → defaults.
        Always use `Settings.resolve/2` to read config.

        ### LLM Models
        - `ministral-3:8b` — Fast, cheap. Used for apprentice neurons.
        - `devstral-small-2:24b` — Reliable tool-calling. Used for journeyman neurons.
        - `claude_haiku` / `claude_sonnet` / `claude_opus` — Cloud models. Configured in Instinct.
        - Fallback chain: `["devstral-small-2:24b"]`

        ### Neuron Ranks
        - **Apprentice** — Simpler tasks, faster model, lower cost
        - **Journeyman** — Complex tasks, capable model, reliable tool use

        ---

        ## 9. Gotchas

        1. **Sandbox allowlist** — Only specific mix commands work. See section 4.
        2. **Snapshot noise** — `test/excessibility/html_snapshots/` files always appear modified. This is normal.
        3. **Format false alarm** — `mix format --check-formatted` exits 1 if snapshots regenerated. Not a real failure.
        4. **Credo baseline** — ~40 pre-existing refactoring issues. Don't file issues for these.
        5. **gemma3:4b** — Installed but breaks on tool-call format. Not in fallback chain.
        6. **ex_cellence** — Starts its own Oban + Repo. Don't duplicate in supervision tree.
        7. **SaladUI textarea** — Uses `value` attr, not inner content.
        8. **Styler** — Formatter plugin rewrites code. Don't fight its changes.
        9. **Warnings = errors** — In test, all warnings are treated as errors.
        10. **Git workflow** — Commit directly to main. No feature branches. No PRs.

        ---

        ## 10. Pages

        | Path | Name | Purpose |
        |------|------|---------|
        | `/cortex` | Cortex | Main dashboard with signals and quick-muse |
        | `/wonder` | Wonder | Pure LLM chat, no data grounding |
        | `/muse` | Muse | Data-grounded chat (RAG over engrams/axioms) |
        | `/thoughts` | Thoughts | Saved query templates |
        | `/neurons` | Neurons | Cluster and agent management |
        | `/ruminations` | Ruminations | Pipeline builder and run history |
        | `/memory` | Memory | Engram browser with tiered drill-down |
        | `/senses` | Senses | Source management and configuration |
        | `/instinct` | Instinct | Settings (LLM providers, API keys, flags) |
        | `/guide` | Guide | Documentation and onboarding |
        | `/evaluate` | Evaluate | Direct evaluation interface |
        | `/settings` | Settings | Additional settings |
        """
      }

      case Lexicon.create_axiom(attrs) do
        {:ok, _} -> Logger.info("[Seeds] Axiom seeded: ex_cortex_system_reference")
        {:error, cs} -> Logger.warning("[Seeds] Axiom failed: #{inspect(cs.errors)}")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Signals
  # ---------------------------------------------------------------------------

  defp seed_signals do
    signals = [
      %{
        title: "Welcome to ExCortex",
        type: "note",
        pinned: true,
        source: "seed",
        tags: ["welcome"],
        body: """
        Welcome to ExCortex — your AI agent orchestration platform.

        ExCortex organizes AI agents into specialized **clusters** that collaborate through
        **ruminations** (multi-step pipelines). Data flows in through **senses**, gets processed
        by **neurons**, and surfaces as **signals** on this dashboard.

        **Where to start:**
        - Browse the **Neurons** page to see your agent teams
        - Try a **Muse** query to chat with your knowledge base
        - Check **Ruminations** to see the available pipelines
        - Visit **Instinct** to configure your LLM providers
        """
      },
      %{
        title: "System Status",
        type: "briefing",
        pinned: true,
        source: "seed",
        tags: ["system", "status"],
        body: """
        ## Seed Data Summary

        The system has been initialized with starter data:

        - **14 clusters** — Research, Writing, Ops/Infra, Triage, Memory Curator, Daily Briefing, Learning, Creative, Devil's Advocate, Sentinel, Translator, Archivist, Therapist, and Dev Team
        - **~26 neurons** — 2-3 specialized agents per cluster
        - **6 ruminations** — Morning Briefing, Sense Intake, Research Digest, Memory Maintenance, Sentinel Sweep, Devil's Review
        - **9 engrams** — Foundational system knowledge
        - **1 axiom** — Comprehensive system reference for agents
        - **6 senses** — Self-Monitor (active), plus 5 paused templates ready for configuration

        ## Status

        - [FYI] Most ruminations are **paused** — activate them in the Ruminations page
        - [FYI] Most senses are **paused** — configure and activate in the Senses page
        - [ACTION] Configure your LLM provider in **Instinct** to enable agent processing
        """
      },
      %{
        title: "Try This First",
        type: "action_list",
        pinned: true,
        source: "seed",
        tags: ["onboarding"],
        metadata: %{
          "items" => [
            %{
              "text" => "Configure an LLM provider in Instinct (/instinct) — Ollama is pre-configured if running locally",
              "done" => false
            },
            %{"text" => "Try a Muse query (/muse) — ask about the cluster map or memory system", "done" => false},
            %{"text" => "Browse Neurons (/neurons) to see your agent teams and their roles", "done" => false},
            %{"text" => "Trigger a rumination (/ruminations) — try Devil's Review with a proposal", "done" => false},
            %{"text" => "Check Memory (/memory) to see the seeded knowledge base", "done" => false}
          ]
        },
        body: "Getting started checklist — complete these steps to explore ExCortex's core features."
      }
    ]

    for signal_attrs <- signals do
      title = signal_attrs.title

      if Repo.exists?(from(s in Signal, where: s.title == ^title and s.source == "seed")) do
        Logger.info("[Seeds] Signal already exists: #{title}")
      else
        case Signals.create_signal(signal_attrs) do
          {:ok, _} -> Logger.info("[Seeds] Signal seeded: #{title}")
          {:error, cs} -> Logger.warning("[Seeds] Signal #{title} failed: #{inspect(cs.errors)}")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Senses
  # ---------------------------------------------------------------------------

  defp seed_senses do
    senses = [
      %{
        name: "Self-Monitor",
        source_type: "cortex",
        status: "active",
        config: %{"interval" => 3_600_000}
      },
      %{
        name: "ExCortex Repo",
        source_type: "github_issues",
        status: "paused",
        config: %{"repo" => "", "label" => "", "interval" => 3_600_000}
      },
      %{
        name: "Project Watch",
        source_type: "directory",
        status: "paused",
        config: %{"path" => "", "extensions" => [".ex", ".exs", ".heex"], "interval" => 300_000}
      },
      %{
        name: "RSS Feed",
        source_type: "feed",
        status: "paused",
        config: %{"url" => "", "interval" => 1_800_000}
      },
      %{
        name: "Email Inbox",
        source_type: "email",
        status: "paused",
        config: %{
          "query" => "tag:unread AND tag:inbox AND NOT tag:classified",
          "interval" => 30_000,
          "max_results" => 15,
          "batch_mode" => true,
          "sort" => "newest-first"
        }
      },
      %{
        name: "Nextcloud",
        source_type: "nextcloud",
        status: "paused",
        config: %{"base_url" => "", "username" => "", "password" => "", "interval" => 1_800_000}
      }
    ]

    for sense_attrs <- senses do
      name = sense_attrs.name

      if Repo.exists?(from(s in Sense, where: s.name == ^name)) do
        Logger.info("[Seeds] Sense already exists: #{name}")
      else
        case Repo.insert(Sense.changeset(%Sense{}, sense_attrs)) do
          {:ok, _} -> Logger.info("[Seeds] Sense seeded: #{name}")
          {:error, cs} -> Logger.warning("[Seeds] Sense #{name} failed: #{inspect(cs.errors)}")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Post-seed wiring (runs after both ruminations and senses exist)
  # ---------------------------------------------------------------------------

  defp wire_email_pipeline do
    email_sense = Repo.one(from(s in Sense, where: s.source_type == "email"))

    if email_sense do
      sense_id = to_string(email_sense.id)

      for name <- ["Email Management Pipeline", "Email Backlog Cleanup"] do
        rumination = Repo.one(from(r in Rumination, where: r.name == ^name))

        if rumination && rumination.source_ids == [] do
          Ruminations.update_rumination(rumination, %{
            trigger: "source",
            source_ids: [sense_id]
          })

          Logger.info("[Seeds] Wired Email Inbox sense → #{name}")
        end
      end
    end
  end

  defp seed_digests do
    alias ExCortex.Senses.Reflex

    for reflex <- Reflex.digests() do
      # Skip if already installed (any sense has this reflex_id)
      if !Repo.exists?(from(s in Sense, where: s.reflex_id == ^reflex.id)) do
        sources = get_in(reflex.default_config, ["sources"]) || []
        tmpl = reflex.rumination_template
        lobe = ExCortex.Lobe.get(reflex.lobe)
        lobe_iterations = if lobe, do: lobe.processing.max_tool_iterations, else: 15

        # Create feed senses
        sense_ids =
          for %{"name" => name, "url" => url} <- sources do
            {:ok, sense} =
              %Sense{}
              |> Sense.changeset(%{
                name: name,
                source_type: "feed",
                config: %{"url" => url, "interval" => 1_800_000},
                reflex_id: reflex.id,
                status: "paused"
              })
              |> Repo.insert()

            to_string(sense.id)
          end

        # Create lobe-shaped pipeline: prepend + core digest + append
        pipeline = if lobe, do: lobe.pipeline, else: %{prepend_steps: [], append_steps: []}
        prepend = Map.get(pipeline, :prepend_steps, [])
        append = Map.get(pipeline, :append_steps, [])

        prepend_synapses =
          for step_type <- prepend do
            step_def = ExCortex.Lobe.pipeline_step_def(step_type, tmpl.cluster, tmpl.gatherer)

            {:ok, s} =
              Ruminations.create_synapse(%{
                name: "#{reflex.name}: #{step_def.name_suffix}",
                description: step_def.description,
                trigger: "manual",
                output_type: step_def.output_type,
                cluster_name: step_def.cluster_name,
                loop_tools: Map.get(step_def, :loop_tools),
                max_tool_iterations: lobe_iterations,
                roster: step_def.roster
              })

            s
          end

        {:ok, s1} =
          Ruminations.create_synapse(%{
            name: "#{reflex.name}: Gather",
            description:
              "Collect the latest items from the feed sources. For each item, extract: title, source, URL, and a 1-sentence summary. " <>
                "IMPORTANT: Always include the original URL for every item — these will be clickable links in the final output. " <>
                "NEVER invent or fabricate details — only report what the source material actually contains. No made-up CVE numbers, names, or statistics. " <>
                "Group items by subtopic. Discard duplicates and items older than #{tmpl.window}.",
            trigger: "manual",
            output_type: "freeform",
            cluster_name: tmpl.cluster,
            loop_tools: ["fetch_url", "web_search"],
            max_tool_iterations: lobe_iterations,
            roster: [%{"who" => "all", "preferred_who" => tmpl.gatherer, "how" => "solo", "when" => "sequential"}]
          })

        {:ok, s2} =
          Ruminations.create_synapse(%{
            name: "#{reflex.name}: Analyze",
            description:
              "Analyze the gathered items. Identify the top 5-10 most significant stories. " <>
                "For each, write a 2-3 sentence analysis explaining why it matters. " <>
                "Preserve the original source URLs — format each story as: **[Title](url)** — analysis. " <>
                "ONLY use facts from the gathered items. Do not add information from outside the provided content. " <>
                "If a detail (version number, CVE, statistic) isn't in the source, don't include it. " <>
                "End with a 'Trends' section noting any patterns across the stories.",
            trigger: "manual",
            output_type: "freeform",
            cluster_name: tmpl.cluster,
            roster: [%{"who" => "all", "preferred_who" => tmpl.analyst, "how" => "solo", "when" => "sequential"}]
          })

        slug = reflex.name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")

        {:ok, s3} =
          Ruminations.create_synapse(%{
            name: "#{reflex.name}: Publish",
            description:
              "Format the analysis as a concise dashboard signal card. Use markdown with clickable links. " <>
                "Structure: brief intro paragraph, then a bulleted list of top stories as **[Title](url)** — one-liner. " <>
                "Keep it scannable — this is a digest, not an essay.",
            trigger: "manual",
            output_type: "signal",
            cluster_name: tmpl.cluster,
            pin_slug: slug,
            pinned: true,
            roster: [%{"who" => "all", "preferred_who" => tmpl.analyst, "how" => "solo", "when" => "sequential"}]
          })

        append_synapses =
          for step_type <- append do
            step_def = ExCortex.Lobe.pipeline_step_def(step_type, tmpl.cluster, tmpl.analyst)

            {:ok, s} =
              Ruminations.create_synapse(%{
                name: "#{reflex.name}: #{step_def.name_suffix}",
                description: step_def.description,
                trigger: "manual",
                output_type: step_def.output_type,
                cluster_name: step_def.cluster_name,
                loop_tools: Map.get(step_def, :loop_tools),
                roster: step_def.roster
              })

            s
          end

        all_synapses = prepend_synapses ++ [s1, s2, s3] ++ append_synapses

        steps =
          all_synapses
          |> Enum.with_index(1)
          |> Enum.map(fn {s, order} -> %{"step_id" => s.id, "order" => order} end)

        {:ok, _} =
          Ruminations.create_rumination(%{
            name: reflex.name,
            description: tmpl.description,
            trigger: "scheduled",
            schedule: tmpl.schedule,
            source_ids: sense_ids,
            status: "paused",
            steps: steps
          })

        Logger.info("[Seeds] Digest installed: #{reflex.name}")
      end
    end
  end
end
