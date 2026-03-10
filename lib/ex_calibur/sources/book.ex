defmodule ExCalibur.Sources.Book do
  @moduledoc false
  defstruct [:id, :name, :description, :source_type, :default_config, :suggested_guild, :kind, :sandbox]

  def all, do: books() ++ scrolls()

  def books do
    [
      # Generic books (need user config)
      %__MODULE__{
        id: "git_repo_watcher",
        name: "Git Repo Watcher",
        description: "Watch a local git repository for new commits and generate diffs for review.",
        source_type: "git",
        default_config: %{"repo_path" => "", "branch" => "main", "interval" => 60_000},
        suggested_guild: "Code Review",
        kind: :book
      },
      %__MODULE__{
        id: "directory_watcher",
        name: "Directory Watcher",
        description: "Monitor a directory for new or changed files.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.txt", "*.md"], "interval" => 30_000},
        suggested_guild: "Content Moderation",
        kind: :book
      },
      %__MODULE__{
        id: "rss_feed",
        name: "RSS/Atom Feed",
        description: "Poll an RSS or Atom feed for new entries.",
        source_type: "feed",
        default_config: %{"url" => "", "interval" => 300_000},
        suggested_guild: nil,
        kind: :book
      },
      %__MODULE__{
        id: "webhook_receiver",
        name: "Webhook Receiver",
        description: "Expose a POST endpoint that accepts data pushes. Supports optional Bearer token auth.",
        source_type: "webhook",
        default_config: %{},
        suggested_guild: nil,
        kind: :book
      },
      %__MODULE__{
        id: "url_watcher",
        name: "URL Watcher",
        description: "Periodically fetch a URL and detect content changes.",
        source_type: "url",
        default_config: %{"url" => "", "interval" => 60_000},
        suggested_guild: nil,
        kind: :book
      },
      %__MODULE__{
        id: "websocket_stream",
        name: "WebSocket Stream",
        description: "Connect to a WebSocket endpoint and process incoming messages.",
        source_type: "websocket",
        default_config: %{"url" => "", "message_path" => "", "interval" => 60_000},
        suggested_guild: nil,
        kind: :book
      },
      # Code Review
      %__MODULE__{
        id: "code_review_pr_webhook",
        name: "GitHub PR Webhook",
        description: "Receive GitHub pull request notifications via webhook for automated review.",
        source_type: "webhook",
        default_config: %{},
        suggested_guild: "Code Review",
        kind: :book
      },
      # Content Moderation
      %__MODULE__{
        id: "content_inbox",
        name: "Content Inbox",
        description: "Watch a directory for user-submitted content awaiting moderation review.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*"], "interval" => 15_000},
        suggested_guild: "Content Moderation",
        kind: :book
      },
      # Accessibility Review
      %__MODULE__{
        id: "accessibility_dir_watcher",
        name: "Excessibility Snapshots",
        description: "Watch excessibility snapshot output directory for new accessibility reports.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.json", "*.html"], "interval" => 30_000},
        suggested_guild: "Accessibility Review",
        kind: :book
      },
      # Performance Audit
      %__MODULE__{
        id: "performance_dir_watcher",
        name: "Excessibility Timelines",
        description: "Watch excessibility timeline JSON output directory for performance data.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.json"], "interval" => 30_000},
        suggested_guild: "Performance Audit",
        kind: :book
      },
      # Incident Triage
      %__MODULE__{
        id: "incident_webhook",
        name: "Error Tracker Alerts",
        description: "Receive alerts from error trackers (Sentry, Honeybadger, etc.) via webhook.",
        source_type: "webhook",
        default_config: %{},
        suggested_guild: "Incident Triage",
        kind: :book
      },
      %__MODULE__{
        id: "incident_status_feed",
        name: "Statuspage Feed",
        description: "RSS feed from service status pages — track upstream dependency incidents.",
        source_type: "feed",
        default_config: %{"url" => "", "interval" => 300_000},
        suggested_guild: "Incident Triage",
        kind: :book
      },
      %__MODULE__{
        id: "incident_ws_stream",
        name: "Log Aggregator Stream",
        description: "Connect to a log aggregator WebSocket stream for real-time error monitoring.",
        source_type: "websocket",
        default_config: %{"url" => "", "message_path" => "", "interval" => 60_000},
        suggested_guild: "Incident Triage",
        kind: :book
      },
      # Contract Review
      %__MODULE__{
        id: "contract_dir_watcher",
        name: "Contracts Folder",
        description: "Watch a contracts/documents directory for new or updated files.",
        source_type: "directory",
        default_config: %{
          "path" => "",
          "patterns" => ["*.pdf", "*.docx", "*.txt", "*.md"],
          "interval" => 30_000
        },
        suggested_guild: "Contract Review",
        kind: :book
      },
      %__MODULE__{
        id: "contract_webhook",
        name: "Document Management Notifications",
        description: "Receive notifications from document management systems when contracts are uploaded or changed.",
        source_type: "webhook",
        default_config: %{},
        suggested_guild: "Contract Review",
        kind: :book
      },
      # Dependency Audit
      %__MODULE__{
        id: "dependency_git_watcher",
        name: "Lock File Watcher",
        description: "Watch a git repo for changes to mix.lock or package.json — triggers audit on dependency updates.",
        source_type: "git",
        default_config: %{"repo_path" => "", "branch" => "main", "interval" => 60_000},
        suggested_guild: "Dependency Audit",
        kind: :book
      },
      # Jira
      %__MODULE__{
        id: "jira_webhook",
        name: "Jira Webhook",
        description: "Receive Jira issue events via webhook — new issues, status changes, priority escalations.",
        source_type: "webhook",
        default_config: %{},
        suggested_guild: "Incident Triage",
        kind: :book
      },
      %__MODULE__{
        id: "jira_feed",
        name: "Jira Activity Feed",
        description: "Poll a Jira board activity feed for new and updated issues.",
        source_type: "feed",
        default_config: %{"url" => "", "interval" => 300_000},
        suggested_guild: nil,
        kind: :book
      },
      # Sandbox-enabled books
      %__MODULE__{
        id: "excessibility_scanner",
        name: "Excessibility Scanner",
        description: "Run excessibility accessibility checks against a Phoenix project.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.ex", "*.heex"], "interval" => 60_000},
        suggested_guild: "Accessibility Review",
        kind: :book,
        sandbox: %{cmd: "mix excessibility", timeout: 120_000}
      },
      %__MODULE__{
        id: "credo_scanner",
        name: "Credo Scanner",
        description: "Run Credo static analysis checks against an Elixir project.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.ex", "*.exs"], "interval" => 60_000},
        suggested_guild: "Code Review",
        kind: :book,
        sandbox: %{cmd: "mix credo --strict", timeout: 120_000}
      },
      %__MODULE__{
        id: "mix_audit_scanner",
        name: "Mix Audit Scanner",
        description: "Run mix audit to check for known vulnerabilities in dependencies.",
        source_type: "git",
        default_config: %{"repo_path" => "", "branch" => "main", "interval" => 300_000},
        suggested_guild: "Dependency Audit",
        kind: :book,
        sandbox: %{cmd: "mix deps.audit", timeout: 120_000}
      },
      %__MODULE__{
        id: "dialyzer_scanner",
        name: "Dialyzer Scanner",
        description: "Run Dialyzer type checking against an Elixir project.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.ex"], "interval" => 120_000},
        suggested_guild: "Code Review",
        kind: :book,
        sandbox: %{cmd: "mix dialyzer", timeout: 300_000}
      },
      %__MODULE__{
        id: "mix_test_runner",
        name: "Test Runner",
        description: "Run the project test suite and feed results to guild members.",
        source_type: "git",
        default_config: %{"repo_path" => "", "branch" => "main", "interval" => 60_000},
        suggested_guild: nil,
        kind: :book,
        sandbox: %{cmd: "mix test", timeout: 300_000}
      },
      %__MODULE__{
        id: "sobelow_scanner",
        name: "Sobelow Security Scanner",
        description: "Run Sobelow security-focused static analysis on a Phoenix project.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.ex", "*.heex"], "interval" => 60_000},
        suggested_guild: "Risk Assessment",
        kind: :book,
        sandbox: %{cmd: "mix sobelow --config", timeout: 120_000}
      },
      # General
      %__MODULE__{
        id: "project_repo_watcher",
        name: "Project Repo Watcher",
        description: "Watch your own project repository for new commits and changes.",
        source_type: "git",
        default_config: %{"repo_path" => "", "branch" => "main", "interval" => 60_000},
        suggested_guild: nil,
        kind: :book
      }
    ]
  end

  def scrolls do
    [
      # Code Review
      %__MODULE__{
        id: "code_review_elixir_forum",
        name: "Elixir Forum",
        description: "Elixir Forum discussions — best practices, code patterns, and community solutions.",
        source_type: "feed",
        default_config: %{"url" => "https://elixirforum.com/posts.rss", "interval" => 1_800_000},
        suggested_guild: "Code Review",
        kind: :scroll
      },
      %__MODULE__{
        id: "code_review_credo_releases",
        name: "Credo Releases",
        description: "Credo static analysis releases — new checks, rule changes, and style updates.",
        source_type: "feed",
        default_config: %{
          "url" => "https://github.com/rrrene/credo/releases.atom",
          "interval" => 86_400_000
        },
        suggested_guild: "Code Review",
        kind: :scroll
      },
      # Content Moderation
      %__MODULE__{
        id: "content_mod_owasp",
        name: "OWASP Blog",
        description: "OWASP Foundation blog — application security, vulnerability research, and best practices.",
        source_type: "feed",
        default_config: %{"url" => "https://owasp.org/feed.xml", "interval" => 3_600_000},
        suggested_guild: "Content Moderation",
        kind: :scroll
      },
      # Risk Assessment
      %__MODULE__{
        id: "risk_krebs",
        name: "Krebs on Security",
        description: "Brian Krebs' investigative security journalism — breaches, threats, and cybercrime.",
        source_type: "feed",
        default_config: %{
          "url" => "https://krebsonsecurity.com/feed/",
          "interval" => 3_600_000
        },
        suggested_guild: "Risk Assessment",
        kind: :scroll
      },
      %__MODULE__{
        id: "risk_cisa_alerts",
        name: "CISA Alerts",
        description: "US Cybersecurity & Infrastructure Security Agency alerts and advisories.",
        source_type: "feed",
        default_config: %{
          "url" => "https://www.cisa.gov/cybersecurity-advisories/all.xml",
          "interval" => 1_800_000
        },
        suggested_guild: "Risk Assessment",
        kind: :scroll
      },
      %__MODULE__{
        id: "risk_nist_nvd",
        name: "NIST NVD Updates",
        description: "NIST National Vulnerability Database — CVE entries and severity scoring.",
        source_type: "url",
        default_config: %{"url" => "https://nvd.nist.gov/", "interval" => 3_600_000},
        suggested_guild: "Risk Assessment",
        kind: :scroll
      },
      %__MODULE__{
        id: "risk_troy_hunt",
        name: "Troy Hunt's Blog",
        description: "Troy Hunt's blog — data breaches, Have I Been Pwned, and web security.",
        source_type: "feed",
        default_config: %{
          "url" => "https://www.troyhunt.com/rss/",
          "interval" => 3_600_000
        },
        suggested_guild: "Risk Assessment",
        kind: :scroll
      },
      # Accessibility Review
      %__MODULE__{
        id: "accessibility_w3c_feed",
        name: "W3C WAI Blog",
        description: "W3C Web Accessibility Initiative blog — guidelines updates, techniques, and best practices.",
        source_type: "feed",
        default_config: %{"url" => "https://www.w3.org/WAI/feed.xml", "interval" => 3_600_000},
        suggested_guild: "Accessibility Review",
        kind: :scroll
      },
      %__MODULE__{
        id: "accessibility_webaim_feed",
        name: "WebAIM Blog",
        description: "WebAIM blog — practical accessibility articles, WCAG interpretation, and testing techniques.",
        source_type: "feed",
        default_config: %{"url" => "https://webaim.org/blog/feed", "interval" => 3_600_000},
        suggested_guild: "Accessibility Review",
        kind: :scroll
      },
      %__MODULE__{
        id: "accessibility_wcag_url",
        name: "WCAG Spec Updates",
        description: "Watch the WCAG specification page for changes and updates.",
        source_type: "url",
        default_config: %{"url" => "https://www.w3.org/TR/WCAG22/", "interval" => 86_400_000},
        suggested_guild: "Accessibility Review",
        kind: :scroll
      },
      # Performance Audit
      %__MODULE__{
        id: "performance_flyio_feed",
        name: "Fly.io Blog",
        description: "Fly.io engineering blog — deployment, infrastructure, and performance insights.",
        source_type: "feed",
        default_config: %{"url" => "https://fly.io/blog/feed.xml", "interval" => 3_600_000},
        suggested_guild: "Performance Audit",
        kind: :scroll
      },
      %__MODULE__{
        id: "performance_dashbit_feed",
        name: "Dashbit Blog",
        description: "Dashbit blog — Elixir performance, Phoenix optimization, and ecosystem updates.",
        source_type: "feed",
        default_config: %{"url" => "https://dashbit.co/blog.atom", "interval" => 3_600_000},
        suggested_guild: "Performance Audit",
        kind: :scroll
      },
      %__MODULE__{
        id: "performance_phoenix_url",
        name: "Phoenix Changelog",
        description: "Watch the Phoenix changelog for new releases and performance-related changes.",
        source_type: "url",
        default_config: %{
          "url" => "https://github.com/phoenixframework/phoenix/blob/main/CHANGELOG.md",
          "interval" => 86_400_000
        },
        suggested_guild: "Performance Audit",
        kind: :scroll
      },
      # Incident Triage
      %__MODULE__{
        id: "incident_hn_feed",
        name: "HN Outage/Incident Feed",
        description: "Hacker News posts about outages, incidents, and postmortems.",
        source_type: "feed",
        default_config: %{
          "url" => "https://hnrss.org/newest?q=outage+OR+incident+OR+postmortem",
          "interval" => 1_800_000
        },
        suggested_guild: "Incident Triage",
        kind: :scroll
      },
      # Contract Review
      %__MODULE__{
        id: "contract_law_feed",
        name: "Law.com Legal News",
        description: "Law.com legal news feed — contract law updates and regulatory changes.",
        source_type: "feed",
        default_config: %{
          "url" => "https://feeds.law.com/law/LegalNews",
          "interval" => 3_600_000
        },
        suggested_guild: "Contract Review",
        kind: :scroll
      },
      # Dependency Audit
      %__MODULE__{
        id: "dependency_ghsa_feed",
        name: "GitHub Advisory Database",
        description: "GitHub Security Advisory database feed — CVEs and vulnerability disclosures.",
        source_type: "feed",
        default_config: %{
          "url" => "https://github.com/advisories.atom",
          "interval" => 1_800_000
        },
        suggested_guild: "Dependency Audit",
        kind: :scroll
      },
      %__MODULE__{
        id: "dependency_elixir_security_feed",
        name: "Elixir Security News",
        description: "Elixir Forum security category — Elixir/Erlang specific vulnerability announcements.",
        source_type: "feed",
        default_config: %{
          "url" => "https://elixirforum.com/c/elixir-news/security/55.rss",
          "interval" => 3_600_000
        },
        suggested_guild: "Dependency Audit",
        kind: :scroll
      },
      %__MODULE__{
        id: "dependency_hex_url",
        name: "Hex.pm Package Updates",
        description: "Watch hex.pm for package updates relevant to your project.",
        source_type: "url",
        default_config: %{"url" => "https://hex.pm/packages", "interval" => 3_600_000},
        suggested_guild: "Dependency Audit",
        kind: :scroll
      },
      # General — no specific guild
      %__MODULE__{
        id: "general_elixir_blog",
        name: "Elixir Lang Blog",
        description: "Official Elixir language blog — releases, announcements, and language updates.",
        source_type: "feed",
        default_config: %{
          "url" => "https://elixir-lang.org/blog.atom",
          "interval" => 86_400_000
        },
        suggested_guild: nil,
        kind: :scroll
      },
      %__MODULE__{
        id: "general_erlang_releases",
        name: "Erlang/OTP Releases",
        description: "Erlang/OTP release notifications — runtime updates that affect your BEAM apps.",
        source_type: "feed",
        default_config: %{
          "url" => "https://github.com/erlang/otp/releases.atom",
          "interval" => 86_400_000
        },
        suggested_guild: nil,
        kind: :scroll
      },
      %__MODULE__{
        id: "general_thinking_elixir",
        name: "Thinking Elixir Podcast",
        description: "Thinking Elixir podcast feed — interviews, news, and deep dives into the Elixir ecosystem.",
        source_type: "feed",
        default_config: %{
          "url" => "https://podcast.thinkingelixir.com/rss",
          "interval" => 86_400_000
        },
        suggested_guild: nil,
        kind: :scroll
      }
    ]
  end

  def get(id), do: Enum.find(all(), &(&1.id == id))
  def for_guild(guild_name), do: Enum.filter(all(), &(&1.suggested_guild == guild_name))
end
