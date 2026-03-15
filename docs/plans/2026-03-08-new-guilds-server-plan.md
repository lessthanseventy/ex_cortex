# New Guilds Server Integration Plan (ex_cortex)

**Design doc:** `docs/plans/2026-03-08-new-guilds-design.md`
**Depends on:** `ex_cellence` charters plan (must be executed first)

Add 5 new guilds to the server: register charter modules in Evaluator/EvaluateLive/GuildHallLive/QuestsLive, add curated Library books for each guild.

---

## Task 1: Add new charters to Evaluator

**File:** `lib/ex_cortex/evaluator.ex`

**Steps:**
1. Add the 5 new charter modules to the `@charters` map:
   ```elixir
   @charters %{
     "Content Moderation" => Excellence.Charters.ContentModeration,
     "Code Review" => Excellence.Charters.CodeReview,
     "Risk Assessment" => Excellence.Charters.RiskAssessment,
     "Accessibility Review" => Excellence.Charters.AccessibilityReview,
     "Performance Audit" => Excellence.Charters.PerformanceAudit,
     "Incident Triage" => Excellence.Charters.IncidentTriage,
     "Contract Review" => Excellence.Charters.ContractReview,
     "Dependency Audit" => Excellence.Charters.DependencyAudit
   }
   ```

**Verify:** `mix compile --warnings-as-errors`

---

## Task 2: Add new charters to EvaluateLive

**File:** `lib/ex_cortex_web/live/evaluate_live.ex`

**Steps:**
1. Add the 5 new entries to the `@charter_keys` map:
   ```elixir
   @charter_keys %{
     "content_moderation" => "Content Moderation",
     "code_review" => "Code Review",
     "risk_assessment" => "Risk Assessment",
     "accessibility_review" => "Accessibility Review",
     "performance_audit" => "Performance Audit",
     "incident_triage" => "Incident Triage",
     "contract_review" => "Contract Review",
     "dependency_audit" => "Dependency Audit"
   }
   ```

**Verify:** `mix compile --warnings-as-errors`

---

## Task 3: Add new charters to GuildHallLive and QuestsLive

**File:** `lib/ex_cortex_web/live/guild_hall_live.ex`

**Steps:**
1. Add the 5 new entries to the `@charters` map:
   ```elixir
   @charters %{
     "Content Moderation" => Excellence.Charters.ContentModeration,
     "Code Review" => Excellence.Charters.CodeReview,
     "Risk Assessment" => Excellence.Charters.RiskAssessment,
     "Accessibility Review" => Excellence.Charters.AccessibilityReview,
     "Performance Audit" => Excellence.Charters.PerformanceAudit,
     "Incident Triage" => Excellence.Charters.IncidentTriage,
     "Contract Review" => Excellence.Charters.ContractReview,
     "Dependency Audit" => Excellence.Charters.DependencyAudit
   }
   ```

**File:** `lib/ex_cortex_web/live/quests_live.ex`

2. Add the same 5 new entries to the `@charters` map (identical to GuildHallLive).

**Verify:** `mix compile --warnings-as-errors`

---

## Task 4: Add Accessibility Review books to Library

**File:** `lib/ex_cortex/sources/book.ex`

**Steps:**
1. Add 4 books to `all/0` for the Accessibility Review guild:
   ```elixir
   %__MODULE__{
     id: "accessibility_dir_watcher",
     name: "Excessibility Snapshots",
     description: "Watch excessibility snapshot output directory for new accessibility reports.",
     source_type: "directory",
     default_config: %{"path" => "", "patterns" => ["*.json", "*.html"], "interval" => 30_000},
     suggested_guild: "Accessibility Review"
   },
   %__MODULE__{
     id: "accessibility_w3c_feed",
     name: "W3C WAI Blog",
     description: "W3C Web Accessibility Initiative blog — guidelines updates, techniques, and best practices.",
     source_type: "feed",
     default_config: %{"url" => "https://www.w3.org/WAI/feed.xml", "interval" => 3_600_000},
     suggested_guild: "Accessibility Review"
   },
   %__MODULE__{
     id: "accessibility_webaim_feed",
     name: "WebAIM Blog",
     description: "WebAIM blog — practical accessibility articles, WCAG interpretation, and testing techniques.",
     source_type: "feed",
     default_config: %{"url" => "https://webaim.org/blog/feed", "interval" => 3_600_000},
     suggested_guild: "Accessibility Review"
   },
   %__MODULE__{
     id: "accessibility_wcag_url",
     name: "WCAG Spec Updates",
     description: "Watch the WCAG specification page for changes and updates.",
     source_type: "url",
     default_config: %{"url" => "https://www.w3.org/TR/WCAG22/", "interval" => 86_400_000},
     suggested_guild: "Accessibility Review"
   }
   ```

**Verify:** `mix compile --warnings-as-errors`

---

## Task 5: Add Performance Audit books to Library

**File:** `lib/ex_cortex/sources/book.ex`

**Steps:**
1. Add 4 books to `all/0` for the Performance Audit guild:
   ```elixir
   %__MODULE__{
     id: "performance_dir_watcher",
     name: "Excessibility Timelines",
     description: "Watch excessibility timeline JSON output directory for performance data.",
     source_type: "directory",
     default_config: %{"path" => "", "patterns" => ["*.json"], "interval" => 30_000},
     suggested_guild: "Performance Audit"
   },
   %__MODULE__{
     id: "performance_flyio_feed",
     name: "Fly.io Blog",
     description: "Fly.io engineering blog — deployment, infrastructure, and performance insights.",
     source_type: "feed",
     default_config: %{"url" => "https://fly.io/blog/feed.xml", "interval" => 3_600_000},
     suggested_guild: "Performance Audit"
   },
   %__MODULE__{
     id: "performance_dashbit_feed",
     name: "Dashbit Blog",
     description: "Dashbit blog — Elixir performance, Phoenix optimization, and ecosystem updates.",
     source_type: "feed",
     default_config: %{"url" => "https://dashbit.co/blog.atom", "interval" => 3_600_000},
     suggested_guild: "Performance Audit"
   },
   %__MODULE__{
     id: "performance_phoenix_url",
     name: "Phoenix Changelog",
     description: "Watch the Phoenix changelog for new releases and performance-related changes.",
     source_type: "url",
     default_config: %{"url" => "https://github.com/phoenixframework/phoenix/blob/main/CHANGELOG.md", "interval" => 86_400_000},
     suggested_guild: "Performance Audit"
   }
   ```

**Verify:** `mix compile --warnings-as-errors`

---

## Task 6: Add Incident Triage books to Library

**File:** `lib/ex_cortex/sources/book.ex`

**Steps:**
1. Add 4 books to `all/0` for the Incident Triage guild:
   ```elixir
   %__MODULE__{
     id: "incident_webhook",
     name: "Error Tracker Alerts",
     description: "Receive alerts from error trackers (Sentry, Honeybadger, etc.) via webhook.",
     source_type: "webhook",
     default_config: %{},
     suggested_guild: "Incident Triage"
   },
   %__MODULE__{
     id: "incident_hn_feed",
     name: "HN Outage/Incident Feed",
     description: "Hacker News posts about outages, incidents, and postmortems.",
     source_type: "feed",
     default_config: %{"url" => "https://hnrss.org/newest?q=outage+OR+incident+OR+postmortem", "interval" => 1_800_000},
     suggested_guild: "Incident Triage"
   },
   %__MODULE__{
     id: "incident_status_feed",
     name: "Statuspage Feed",
     description: "RSS feed from service status pages — track upstream dependency incidents.",
     source_type: "feed",
     default_config: %{"url" => "", "interval" => 300_000},
     suggested_guild: "Incident Triage"
   },
   %__MODULE__{
     id: "incident_ws_stream",
     name: "Log Aggregator Stream",
     description: "Connect to a log aggregator WebSocket stream for real-time error monitoring.",
     source_type: "websocket",
     default_config: %{"url" => "", "message_path" => "", "interval" => 60_000},
     suggested_guild: "Incident Triage"
   }
   ```

**Verify:** `mix compile --warnings-as-errors`

---

## Task 7: Add Contract Review books to Library

**File:** `lib/ex_cortex/sources/book.ex`

**Steps:**
1. Add 3 books to `all/0` for the Contract Review guild:
   ```elixir
   %__MODULE__{
     id: "contract_dir_watcher",
     name: "Contracts Folder",
     description: "Watch a contracts/documents directory for new or updated files.",
     source_type: "directory",
     default_config: %{"path" => "", "patterns" => ["*.pdf", "*.docx", "*.txt", "*.md"], "interval" => 30_000},
     suggested_guild: "Contract Review"
   },
   %__MODULE__{
     id: "contract_law_feed",
     name: "Law.com Legal News",
     description: "Law.com legal news feed — contract law updates and regulatory changes.",
     source_type: "feed",
     default_config: %{"url" => "https://feeds.law.com/law/LegalNews", "interval" => 3_600_000},
     suggested_guild: "Contract Review"
   },
   %__MODULE__{
     id: "contract_webhook",
     name: "Document Management Notifications",
     description: "Receive notifications from document management systems when contracts are uploaded or changed.",
     source_type: "webhook",
     default_config: %{},
     suggested_guild: "Contract Review"
   }
   ```

**Verify:** `mix compile --warnings-as-errors`

---

## Task 8: Add Dependency Audit books to Library

**File:** `lib/ex_cortex/sources/book.ex`

**Steps:**
1. Add 4 books to `all/0` for the Dependency Audit guild:
   ```elixir
   %__MODULE__{
     id: "dependency_git_watcher",
     name: "Lock File Watcher",
     description: "Watch a git repo for changes to mix.lock or package.json — triggers audit on dependency updates.",
     source_type: "git",
     default_config: %{"repo_path" => "", "branch" => "main", "interval" => 60_000},
     suggested_guild: "Dependency Audit"
   },
   %__MODULE__{
     id: "dependency_ghsa_feed",
     name: "GitHub Advisory Database",
     description: "GitHub Security Advisory database feed — CVEs and vulnerability disclosures.",
     source_type: "feed",
     default_config: %{"url" => "https://github.com/advisories.atom", "interval" => 1_800_000},
     suggested_guild: "Dependency Audit"
   },
   %__MODULE__{
     id: "dependency_elixir_security_feed",
     name: "Elixir Security News",
     description: "Elixir Forum security category — Elixir/Erlang specific vulnerability announcements.",
     source_type: "feed",
     default_config: %{"url" => "https://elixirforum.com/c/elixir-news/security/55.rss", "interval" => 3_600_000},
     suggested_guild: "Dependency Audit"
   },
   %__MODULE__{
     id: "dependency_hex_url",
     name: "Hex.pm Package Updates",
     description: "Watch hex.pm for package updates relevant to your project.",
     source_type: "url",
     default_config: %{"url" => "https://hex.pm/packages", "interval" => 3_600_000},
     suggested_guild: "Dependency Audit"
   }
   ```

**Verify:** `mix compile --warnings-as-errors`

---

## Task 9: Update tests

**File:** `test/ex_cortex_web/live/library_live_test.exs`

**Steps:**
1. Update the test to assert all new book names are rendered. The existing test checks for the 6 generic books. Add assertions for the new guild-specific books:
   ```elixir
   # Accessibility Review books
   assert html =~ "Excessibility Snapshots"
   assert html =~ "W3C WAI Blog"
   assert html =~ "WebAIM Blog"
   assert html =~ "WCAG Spec Updates"

   # Performance Audit books
   assert html =~ "Excessibility Timelines"
   assert html =~ "Fly.io Blog"
   assert html =~ "Dashbit Blog"
   assert html =~ "Phoenix Changelog"

   # Incident Triage books
   assert html =~ "Error Tracker Alerts"
   assert html =~ "HN Outage/Incident Feed"
   assert html =~ "Statuspage Feed"
   assert html =~ "Log Aggregator Stream"

   # Contract Review books
   assert html =~ "Contracts Folder"
   assert html =~ "Law.com Legal News"
   assert html =~ "Document Management Notifications"

   # Dependency Audit books
   assert html =~ "Lock File Watcher"
   assert html =~ "GitHub Advisory Database"
   assert html =~ "Elixir Security News"
   assert html =~ "Hex.pm Package Updates"
   ```

**Verify:** `mix test test/ex_cortex_web/live/library_live_test.exs`

---

## Task 10: Full verification

**Steps:**
1. `mix format`
2. `mix compile --warnings-as-errors`
3. `mix test`

**Verify:** All pass cleanly.
