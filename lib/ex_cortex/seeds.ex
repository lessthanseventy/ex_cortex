defmodule ExCortex.Seeds do
  @moduledoc "Seeds the database with starter clusters, neurons, ruminations, engrams, signals, senses, and axioms."

  import Ecto.Query

  alias ExCortex.Clusters
  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo
  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Rumination

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
        rank: "apprentice",
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
        rank: "apprentice",
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
        rank: "apprentice",
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

  defp seed_engrams, do: :ok
  defp seed_axioms, do: :ok
  defp seed_signals, do: :ok
  defp seed_senses, do: :ok
end
