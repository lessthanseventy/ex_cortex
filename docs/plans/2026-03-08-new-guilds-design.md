# New Guilds Design

## Overview

Five new guilds to expand the Guild Hall catalog, each with curated Library books (including relevant news feeds). These complement the existing three guilds (Content Moderation, Code Review, Risk Assessment).

---

## Accessibility Review Guild

**Description:** Multi-agent accessibility compliance and usability review pipeline

**Roles:**

1. **wcag-auditor** — Evaluates against WCAG 2.1/2.2 success criteria. Checks semantic HTML, ARIA usage, color contrast, keyboard navigation, focus management.
   - Perspectives: "strict" (AAA compliance, gemma3:4b, cod), "practical" (AA with pragmatic trade-offs, phi4-mini, cot)

2. **usability-reviewer** — Evaluates from a user experience perspective. Screen reader flow, cognitive load, error recovery, form labeling, touch target sizing.
   - Perspectives: "alpha" (gemma3:4b, cod), "beta" (phi4-mini, cot)

3. **assistive-tech-analyst** — Evaluates compatibility with assistive technologies. Screen readers, voice control, switch devices, magnification. Flags patterns known to break specific AT.
   - Perspectives: "alpha" (gemma3:4b, cod), "beta" (phi4-mini, cot)

**Actions:** `[:pass, :warn, :fail, :escalate]`

**Strategy:** `{:role_veto, veto_roles: [:wcag_auditor]}`

**Default Books:**
- Directory Watcher — excessibility snapshot output
- RSS Feed — W3C WAI blog (https://www.w3.org/WAI/feed.xml)
- RSS Feed — WebAIM blog (https://webaim.org/blog/feed)
- URL Watcher — WCAG spec updates

---

## Performance Audit Guild

**Description:** Multi-agent performance analysis and resource optimization pipeline

**Roles:**

1. **bottleneck-detector** — Identifies performance hotspots: slow queries, N+1 patterns, blocking operations, excessive re-renders, long task chains.
   - Perspectives: "thorough" (gemma3:4b, cod), "quick" (phi4-mini, cot)

2. **memory-analyst** — Evaluates memory usage patterns: leaks, unbounded growth, large allocations, process mailbox buildup, ETS table bloat.
   - Perspectives: "conservative" (gemma3:4b, cod), "balanced" (phi4-mini, cot)

3. **resource-enforcer** — Evaluates against performance budgets: response times, bundle sizes, database connection pools, CPU utilization thresholds. Flags regressions from baseline.
   - Perspectives: "alpha" (gemma3:4b, cod), "beta" (phi4-mini, cot)

**Actions:** `[:pass, :warn, :fail, :escalate]`

**Strategy:** `{:weighted, weights: %{bottleneck_detector: 1.0, memory_analyst: 1.2, resource_enforcer: 1.0}}`

**Default Books:**
- Directory Watcher — excessibility timeline JSON output
- RSS Feed — Fly.io blog (https://fly.io/blog/feed.xml)
- RSS Feed — Dashbit blog (https://dashbit.co/blog.atom)
- URL Watcher — Phoenix changelog

---

## Incident Triage Guild

**Description:** Multi-agent incident severity assessment and response routing pipeline

**Roles:**

1. **impact-assessor** — Evaluates blast radius: how many users affected, which systems impacted, revenue implications, data integrity risks. Distinguishes between degraded and fully down.
   - Perspectives: "conservative" (gemma3:4b, cod), "measured" (phi4-mini, cot)

2. **root-cause-analyst** — Analyzes symptoms to identify likely root cause categories: infrastructure, deployment, dependency, data, traffic spike, security breach. Looks for correlating signals.
   - Perspectives: "alpha" (gemma3:4b, cod), "beta" (phi4-mini, cot)

3. **escalation-router** — Determines urgency and routing: page on-call, notify team lead, create ticket, or monitor. Considers time of day, blast radius, and whether self-healing is likely.
   - Perspectives: "alpha" (gemma3:4b, cod), "beta" (phi4-mini, cot)

**Actions:** `[:monitor, :alert, :page, :escalate]`

**Strategy:** `{:role_veto, veto_roles: [:impact_assessor]}`

**Default Books:**
- Webhook Receiver — error tracker alerts (Sentry, Honeybadger, etc.)
- RSS Feed — Hacker News (https://hnrss.org/newest?q=outage+OR+incident+OR+postmortem)
- RSS Feed — Statuspage feeds
- WebSocket Stream — log aggregator stream

---

## Contract Review Guild

**Description:** Multi-agent document risk analysis and obligation tracking pipeline

**Roles:**

1. **risk-evaluator** — Evaluates legal and financial exposure: liability clauses, indemnification, limitation of liability, termination penalties, IP assignment. Flags one-sided or unusual terms.
   - Perspectives: "conservative" (gemma3:4b, cod), "pragmatic" (phi4-mini, cot)

2. **obligation-tracker** — Identifies commitments and deadlines: deliverables, SLAs, payment terms, renewal dates, notice periods, reporting requirements. Surfaces things you'd need to actually do.
   - Perspectives: "alpha" (gemma3:4b, cod), "beta" (phi4-mini, cot)

3. **ambiguity-detector** — Finds vague, contradictory, or missing terms: undefined key terms, conflicting clauses, implicit assumptions, missing standard protections (force majeure, dispute resolution, governing law).
   - Perspectives: "alpha" (gemma3:4b, cod), "beta" (phi4-mini, cot)

**Actions:** `[:accept, :flag, :reject, :escalate]`

**Strategy:** `:majority`

**Default Books:**
- Directory Watcher — contracts/documents folder
- RSS Feed — Law.com (https://feeds.law.com/law/LegalNews)
- Webhook Receiver — document management system notifications

---

## Dependency Audit Guild

**Description:** Multi-agent dependency health and supply chain security pipeline

**Roles:**

1. **vulnerability-scanner** — Evaluates known CVEs, security advisories, and exploit availability for dependencies. Checks transitive dependencies. Considers severity, exploitability, and whether the vulnerable code path is actually used.
   - Perspectives: "thorough" (gemma3:4b, cod), "quick" (phi4-mini, cot)

2. **license-checker** — Evaluates license compatibility: copyleft contamination, attribution requirements, commercial use restrictions, patent clauses. Flags license changes between versions.
   - Perspectives: "strict" (gemma3:4b, cod), "permissive" (phi4-mini, cot)

3. **maintenance-evaluator** — Assesses project health: last commit date, open issue count, bus factor, release cadence, breaking change frequency, deprecation status. Flags abandoned or at-risk dependencies.
   - Perspectives: "alpha" (gemma3:4b, cod), "beta" (phi4-mini, cot)

**Actions:** `[:approve, :warn, :block, :escalate]`

**Strategy:** `{:role_veto, veto_roles: [:vulnerability_scanner]}`

**Default Books:**
- Git Watcher — detects mix.lock / package.json changes
- RSS Feed — GitHub Advisory Database (https://github.com/advisories.atom)
- RSS Feed — Elixir Forum security (https://elixirforum.com/c/elixir-news/security/55.rss)
- URL Watcher — hex.pm package updates

---

## Implementation Notes

- Charters go in `ex_cellence` at `lib/excellence/charters/`
- Books go in `ExCellenceServer.Sources.Book` catalogue
- Each guild follows the established pattern: 3 roles, 2 perspectives each, domain-specific actions
- Guild Hall install flow auto-creates default books (paused) via `Book.for_guild/1`
- RSS feed URLs should be verified before shipping — some may need adjustment
