# ExCortex Seed Data Design

**Date:** 2026-03-15
**Goal:** Pre-populate the database with opinionated, useful starter content that doubles as a demo and a personal toolkit. Everything is editable via the UI.

## 1. Clusters (14)

Each cluster gets a pathway description and 2-4 opinionated neurons with real system prompts.

| Cluster | Purpose |
|---|---|
| Dev Team | Code analysis, writing, review, QA, UX. Powers the neuroplasticity loop. |
| Research | Gather, synthesize, extract insights from URLs, feeds, documents. |
| Writing | Draft, edit, tone-check prose — blog posts, docs, comms. |
| Ops/Infra | Monitoring, deploy checks, dependency audits, health checks. |
| Triage | Intake from senses, classify priority/type, route to cluster. |
| Memory Curator | Review engrams, consolidate duplicates, promote important, tag gaps. |
| Daily Briefing | Aggregate signals from senses into morning summary dashboard card. |
| Learning | Extract concepts from articles/papers/videos, create engrams, connect knowledge. |
| Creative | Brainstorming, ideation, lateral thinking. Divergent over convergent. |
| Devil's Advocate | Stress-test proposals and plans, find holes and blind spots. |
| Sentinel | Watch for stale PRs, overdue TODOs, silent failures, forgotten work. |
| Translator | Convert between contexts: technical<>plain, code<>docs, threads<>actions. |
| Archivist | Package engrams/signals into publishable artifacts: changelogs, reports, summaries. |
| Therapist | Tone/sentiment analysis on inputs. Social signal processing. |

## 2. Neurons (~40 total)

Key neurons per cluster, all type "role", status "active", with real system prompts and tool configs:

- **Dev Team:** analyst, pm, code_writer, code_reviewer, qa, ux_designer
- **Research:** gatherer, analyst, summarizer
- **Writing:** drafter, editor, tone_checker
- **Ops/Infra:** monitor, auditor
- **Triage:** classifier, router
- **Memory Curator:** curator_scanner, consolidator, tagger
- **Daily Briefing:** aggregator, editor
- **Learning:** extractor, connector
- **Creative:** diverger, connector
- **Devil's Advocate:** critic, steelman
- **Sentinel:** watcher, alerter
- **Translator:** translator, formatter
- **Archivist:** collector, packager
- **Therapist:** sensor, advisor

## 3. Ruminations (8 starter pipelines)

| Rumination | Trigger | Steps | Output |
|---|---|---|---|
| Morning Briefing | scheduled (daily), starts paused | aggregator -> editor -> signal | Briefing card on dashboard |
| Neuroplasticity: Analyst Sweep | scheduled (4h), starts paused | analyst -> pm -> github_issue | SI issues on GitHub |
| Neuroplasticity: Fix Loop | cortex trigger | pm_triage -> code_writer -> code_reviewer -> qa -> ux -> pm_merge | Merged fix |
| Sense Intake | source trigger | classifier -> router | Routed to cluster |
| Research Digest | manual | gatherer -> analyst -> summarizer -> engram | Engram with structured knowledge |
| Memory Maintenance | scheduled (weekly), starts paused | curator_scan -> consolidator -> tagger | Cleaned-up memory |
| Sentinel Sweep | scheduled (daily), starts paused | watcher -> alerter -> signal | Alert cards |
| Devil's Review | manual | critic -> steelman -> signal | Stress-test report |

## 4. Engrams (starter knowledge)

**Semantic:** ExCortex Cluster Map, Memory Tier System, Signal Types Guide, Sense Types Overview
**Procedural:** Writing Effective Synapse Rosters, Prompt Engineering for Neurons, When to Escalate, Memory Extraction Patterns
**Episodic:** Seed Bootstrap record

All with pre-generated L0 impressions and L1 recalls.

## 5. Axiom: "ExCortex System Reference"

Comprehensive markdown axiom — the LLM playbook. Covers vocabulary, architecture, tools, conventions, cluster responsibilities, handoff patterns. Agents query via `query_axiom`.

## 6. Signals (3 welcome cards)

- **Welcome to ExCortex** (note, pinned) — orientation
- **System Status** (briefing, pinned) — seeded clusters, sense status, LLM providers
- **Try This First** (action_list, pinned) — getting-started checklist

## 7. Senses (6, mostly paused)

| Sense | Type | Status | Notes |
|---|---|---|---|
| Self-Monitor | cortex | active | No external deps |
| ExCortex Repo | github_issues | paused | Needs repo path |
| Project Watch | directory | paused | Needs path confirmation |
| RSS/Atom Feed | feed | paused | Needs feed URLs |
| Email Inbox | email | paused | Needs mail config |
| Nextcloud | nextcloud | paused | Needs server URL + credentials |

## 8. Guide Page Content

Flesh out `/guide` with user-facing documentation covering:
- What ExCortex is and the brain vocabulary
- Screen-by-screen walkthrough
- Getting started workflow
- How to configure LLM providers
- How to create your first rumination

## Implementation Notes

- All seed data goes in `priv/repo/seeds.exs` (extend existing file)
- Idempotent — safe to run multiple times (check before insert)
- Scheduled ruminations start paused so they don't fire without LLM config
- Senses start paused (except cortex) so they don't error without credentials
- Neurons get real system prompts, not placeholders
