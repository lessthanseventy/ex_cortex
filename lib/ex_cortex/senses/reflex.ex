defmodule ExCortex.Senses.Reflex do
  @moduledoc false
  defstruct [:id, :name, :description, :source_type, :default_config, :suggested_cluster, :kind, :sandbox, banner: nil]

  def all, do: reflexes() ++ streams()

  def reflexes do
    [
      # Generic reflexes (need user config)
      %__MODULE__{
        id: "git_repo_watcher",
        banner: :tech,
        name: "Git Repo Watcher",
        description: "Watch a local git repository for new commits and generate diffs for review.",
        source_type: "git",
        default_config: %{"repo_path" => "", "branch" => "main", "interval" => 60_000},
        suggested_cluster: "Code Review",
        kind: :reflex
      },
      %__MODULE__{
        id: "directory_watcher",
        banner: :lifestyle,
        name: "Directory Watcher",
        description: "Monitor a directory for new or changed files.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.txt", "*.md"], "interval" => 30_000},
        suggested_cluster: "Content Moderation",
        kind: :reflex
      },
      %__MODULE__{
        id: "rss_feed",
        name: "RSS/Atom Feed",
        description: "Poll an RSS or Atom feed for new entries.",
        source_type: "feed",
        default_config: %{"url" => "", "interval" => 300_000},
        suggested_cluster: nil,
        kind: :reflex
      },
      %__MODULE__{
        id: "webhook_receiver",
        name: "Webhook Receiver",
        description: "Expose a POST endpoint that accepts data pushes. Supports optional Bearer token auth.",
        source_type: "webhook",
        default_config: %{},
        suggested_cluster: nil,
        kind: :reflex
      },
      %__MODULE__{
        id: "url_watcher",
        name: "URL Watcher",
        description: "Periodically fetch a URL and detect content changes.",
        source_type: "url",
        default_config: %{"url" => "", "interval" => 60_000},
        suggested_cluster: nil,
        kind: :reflex
      },
      %__MODULE__{
        id: "websocket_stream",
        name: "WebSocket Stream",
        description: "Connect to a WebSocket endpoint and process incoming messages.",
        source_type: "websocket",
        default_config: %{"url" => "", "message_path" => "", "interval" => 60_000},
        suggested_cluster: nil,
        kind: :reflex
      },
      # Everyday Council
      %__MODULE__{
        id: "everyday_council_intake",
        banner: :lifestyle,
        name: "Personal Intake",
        description:
          "Webhook endpoint for dropping in links, notes, PDFs, or thoughts for the Journal Keeper to process.",
        source_type: "webhook",
        default_config: %{},
        suggested_cluster: "Everyday Council",
        kind: :reflex
      },
      %__MODULE__{
        id: "obsidian_watcher",
        banner: :lifestyle,
        name: "Obsidian Watcher",
        description: "Watch an Obsidian vault folder for new or changed notes and process them automatically.",
        source_type: "obsidian",
        default_config: %{"interval" => 60_000},
        suggested_cluster: "Everyday Council",
        kind: :reflex
      },
      %__MODULE__{
        id: "email_inbox",
        banner: :lifestyle,
        name: "Email Inbox",
        description: "Monitor your notmuch email database for new messages and feed them into the council.",
        source_type: "email",
        default_config: %{"query" => "tag:new", "interval" => 300_000, "limit" => 50},
        suggested_cluster: "Everyday Council",
        kind: :reflex
      },
      %__MODULE__{
        id: "youtube_channel",
        banner: :lifestyle,
        name: "YouTube Channel",
        description: "Monitor a YouTube channel or playlist for new videos via yt-dlp.",
        source_type: "media",
        default_config: %{"url" => "", "interval" => 3_600_000},
        suggested_cluster: nil,
        kind: :reflex
      },
      # Code Review
      %__MODULE__{
        id: "code_review_pr_webhook",
        banner: :tech,
        name: "GitHub PR Webhook",
        description: "Receive GitHub pull request notifications via webhook for automated review.",
        source_type: "webhook",
        default_config: %{},
        suggested_cluster: "Code Review",
        kind: :reflex
      },
      # Dev Team
      %__MODULE__{
        id: "github_issue_watcher",
        banner: :tech,
        name: "GitHub Issue Watcher",
        description:
          "Watches a GitHub repository for open issues with a specific label. Use with the Dev Team cluster to automatically pick up and work self-improvement issues.",
        source_type: "github_issues",
        default_config: %{"repo" => "", "label" => "self-improvement", "interval" => 300_000},
        suggested_cluster: "Dev Team",
        kind: :reflex
      },
      # Content Moderation
      %__MODULE__{
        id: "content_inbox",
        banner: :lifestyle,
        name: "Content Inbox",
        description: "Watch a directory for user-submitted content awaiting moderation review.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*"], "interval" => 15_000},
        suggested_cluster: "Content Moderation",
        kind: :reflex
      },
      # Accessibility Review
      %__MODULE__{
        id: "accessibility_dir_watcher",
        banner: :tech,
        name: "Excessibility Snapshots",
        description: "Watch excessibility snapshot output directory for new accessibility reports.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.json", "*.html"], "interval" => 30_000},
        suggested_cluster: "Accessibility Review",
        kind: :reflex
      },
      # Performance Audit
      %__MODULE__{
        id: "performance_dir_watcher",
        banner: :tech,
        name: "Excessibility Timelines",
        description: "Watch excessibility timeline JSON output directory for performance data.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.json"], "interval" => 30_000},
        suggested_cluster: "Performance Audit",
        kind: :reflex
      },
      # Incident Triage
      %__MODULE__{
        id: "incident_webhook",
        banner: :tech,
        name: "Error Tracker Alerts",
        description: "Receive alerts from error trackers (Sentry, Honeybadger, etc.) via webhook.",
        source_type: "webhook",
        default_config: %{},
        suggested_cluster: "Incident Triage",
        kind: :reflex
      },
      %__MODULE__{
        id: "incident_status_feed",
        banner: :tech,
        name: "Statuspage Feed",
        description: "RSS feed from service status pages — track upstream dependency incidents.",
        source_type: "feed",
        default_config: %{"url" => "", "interval" => 300_000},
        suggested_cluster: "Incident Triage",
        kind: :reflex
      },
      %__MODULE__{
        id: "incident_ws_stream",
        banner: :tech,
        name: "Log Aggregator Stream",
        description: "Connect to a log aggregator WebSocket stream for real-time error monitoring.",
        source_type: "websocket",
        default_config: %{"url" => "", "message_path" => "", "interval" => 60_000},
        suggested_cluster: "Incident Triage",
        kind: :reflex
      },
      # Contract Review
      %__MODULE__{
        id: "contract_dir_watcher",
        banner: :business,
        name: "Contracts Folder",
        description: "Watch a contracts/documents directory for new or updated files.",
        source_type: "directory",
        default_config: %{
          "path" => "",
          "patterns" => ["*.pdf", "*.docx", "*.txt", "*.md"],
          "interval" => 30_000
        },
        suggested_cluster: "Contract Review",
        kind: :reflex
      },
      %__MODULE__{
        id: "contract_webhook",
        banner: :business,
        name: "Document Management Notifications",
        description: "Receive notifications from document management systems when contracts are uploaded or changed.",
        source_type: "webhook",
        default_config: %{},
        suggested_cluster: "Contract Review",
        kind: :reflex
      },
      # Dependency Audit
      %__MODULE__{
        id: "dependency_git_watcher",
        banner: :tech,
        name: "Lock File Watcher",
        description: "Watch a git repo for changes to mix.lock or package.json — triggers audit on dependency updates.",
        source_type: "git",
        default_config: %{"repo_path" => "", "branch" => "main", "interval" => 60_000},
        suggested_cluster: "Dependency Audit",
        kind: :reflex
      },
      # Jira
      %__MODULE__{
        id: "jira_webhook",
        banner: :tech,
        name: "Jira Webhook",
        description: "Receive Jira issue events via webhook — new issues, status changes, priority escalations.",
        source_type: "webhook",
        default_config: %{},
        suggested_cluster: "Incident Triage",
        kind: :reflex
      },
      %__MODULE__{
        id: "jira_feed",
        name: "Jira Activity Feed",
        description: "Poll a Jira board activity feed for new and updated issues.",
        source_type: "feed",
        default_config: %{"url" => "", "interval" => 300_000},
        suggested_cluster: nil,
        kind: :reflex
      },
      # Sandbox-enabled reflexes
      %__MODULE__{
        id: "excessibility_scanner",
        banner: :tech,
        name: "Excessibility Scanner",
        description: "Run excessibility accessibility checks against a Phoenix project.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.ex", "*.heex"], "interval" => 60_000},
        suggested_cluster: "Accessibility Review",
        kind: :reflex,
        sandbox: %{cmd: "mix excessibility", timeout: 120_000}
      },
      %__MODULE__{
        id: "credo_scanner",
        banner: :tech,
        name: "Credo Scanner",
        description: "Run Credo static analysis checks against an Elixir project.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.ex", "*.exs"], "interval" => 60_000},
        suggested_cluster: "Code Review",
        kind: :reflex,
        sandbox: %{cmd: "mix credo --strict", timeout: 120_000}
      },
      %__MODULE__{
        id: "mix_audit_scanner",
        banner: :tech,
        name: "Mix Audit Scanner",
        description: "Run mix audit to check for known vulnerabilities in dependencies.",
        source_type: "git",
        default_config: %{"repo_path" => "", "branch" => "main", "interval" => 300_000},
        suggested_cluster: "Dependency Audit",
        kind: :reflex,
        sandbox: %{cmd: "mix deps.audit", timeout: 120_000}
      },
      %__MODULE__{
        id: "dialyzer_scanner",
        banner: :tech,
        name: "Dialyzer Scanner",
        description: "Run Dialyzer type checking against an Elixir project.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.ex"], "interval" => 120_000},
        suggested_cluster: "Code Review",
        kind: :reflex,
        sandbox: %{cmd: "mix dialyzer", timeout: 300_000}
      },
      %__MODULE__{
        id: "mix_test_runner",
        name: "Test Runner",
        description: "Run the project test suite and feed results to cluster neurons.",
        source_type: "git",
        default_config: %{"repo_path" => "", "branch" => "main", "interval" => 60_000},
        suggested_cluster: nil,
        kind: :reflex,
        sandbox: %{cmd: "mix test", timeout: 300_000}
      },
      %__MODULE__{
        id: "sobelow_scanner",
        banner: :tech,
        name: "Sobelow Security Scanner",
        description: "Run Sobelow security-focused static analysis on a Phoenix project.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.ex", "*.heex"], "interval" => 60_000},
        suggested_cluster: "Risk Assessment",
        kind: :reflex,
        sandbox: %{cmd: "mix sobelow --config", timeout: 120_000}
      },
      # General
      %__MODULE__{
        id: "project_repo_watcher",
        name: "Project Repo Watcher",
        description: "Watch your own project repository for new commits and changes.",
        source_type: "git",
        default_config: %{"repo_path" => "", "branch" => "main", "interval" => 60_000},
        suggested_cluster: nil,
        kind: :reflex
      },
      # Nextcloud
      %__MODULE__{
        id: "nextcloud_files",
        banner: :lifestyle,
        name: "Nextcloud Files",
        description: "Watch a Nextcloud folder for new and changed files.",
        source_type: "nextcloud",
        default_config: %{"watch_path" => "/Documents", "interval" => 60_000},
        suggested_cluster: nil,
        kind: :reflex
      },
      %__MODULE__{
        id: "nextcloud_notes",
        banner: :lifestyle,
        name: "Nextcloud Notes",
        description: "Monitor Nextcloud Notes for new entries and changes.",
        source_type: "nextcloud",
        default_config: %{"watch_type" => "notes", "interval" => 120_000},
        suggested_cluster: nil,
        kind: :reflex
      },
      %__MODULE__{
        id: "nextcloud_calendar",
        banner: :lifestyle,
        name: "Nextcloud Calendar",
        description: "Watch Nextcloud Calendar for upcoming events and changes.",
        source_type: "nextcloud",
        default_config: %{"watch_type" => "calendar", "interval" => 300_000},
        suggested_cluster: nil,
        kind: :reflex
      },
      %__MODULE__{
        id: "nextcloud_talk",
        banner: :lifestyle,
        name: "Nextcloud Talk",
        description: "Monitor Nextcloud Talk conversations for new messages.",
        source_type: "nextcloud",
        default_config: %{"watch_type" => "talk", "interval" => 30_000},
        suggested_cluster: nil,
        kind: :reflex
      },
      %__MODULE__{
        id: "signal_watcher",
        name: "Signal Card Watcher",
        description:
          "Watch signal cards for new or changed entries. Filter by card type and/or tags to feed specific cards into thoughts.",
        source_type: "cortex",
        default_config: %{"type_filter" => [], "tag_filter" => [], "interval" => 30_000},
        suggested_cluster: nil,
        kind: :reflex
      }
    ]
  end

  def streams do
    [
      # Code Review
      %__MODULE__{
        id: "code_review_elixir_forum",
        banner: :tech,
        name: "Elixir Forum",
        description: "Elixir Forum discussions — best practices, code patterns, and community solutions.",
        source_type: "feed",
        default_config: %{"url" => "https://elixirforum.com/posts.rss", "interval" => 1_800_000},
        suggested_cluster: "Code Review",
        kind: :stream
      },
      %__MODULE__{
        id: "code_review_credo_releases",
        banner: :tech,
        name: "Credo Releases",
        description: "Credo static analysis releases — new checks, rule changes, and style updates.",
        source_type: "feed",
        default_config: %{
          "url" => "https://github.com/rrrene/credo/releases.atom",
          "interval" => 86_400_000
        },
        suggested_cluster: "Code Review",
        kind: :stream
      },
      # Content Moderation
      %__MODULE__{
        id: "content_mod_owasp",
        banner: :lifestyle,
        name: "OWASP Blog",
        description: "OWASP Foundation blog — application security, vulnerability research, and best practices.",
        source_type: "feed",
        default_config: %{"url" => "https://owasp.org/feed.xml", "interval" => 3_600_000},
        suggested_cluster: "Content Moderation",
        kind: :stream
      },
      # Risk Assessment
      %__MODULE__{
        id: "risk_krebs",
        banner: :tech,
        name: "Krebs on Security",
        description: "Brian Krebs' investigative security journalism — breaches, threats, and cybercrime.",
        source_type: "feed",
        default_config: %{
          "url" => "https://krebsonsecurity.com/feed/",
          "interval" => 3_600_000
        },
        suggested_cluster: "Risk Assessment",
        kind: :stream
      },
      %__MODULE__{
        id: "risk_cisa_alerts",
        banner: :tech,
        name: "CISA Alerts",
        description: "US Cybersecurity & Infrastructure Security Agency alerts and advisories.",
        source_type: "feed",
        default_config: %{
          "url" => "https://www.cisa.gov/cybersecurity-advisories/all.xml",
          "interval" => 1_800_000
        },
        suggested_cluster: "Risk Assessment",
        kind: :stream
      },
      %__MODULE__{
        id: "risk_nist_nvd",
        banner: :tech,
        name: "NIST NVD Updates",
        description: "NIST National Vulnerability Database — CVE entries and severity scoring.",
        source_type: "url",
        default_config: %{"url" => "https://nvd.nist.gov/", "interval" => 3_600_000},
        suggested_cluster: "Risk Assessment",
        kind: :stream
      },
      %__MODULE__{
        id: "risk_troy_hunt",
        banner: :tech,
        name: "Troy Hunt's Blog",
        description: "Troy Hunt's blog — data breaches, Have I Been Pwned, and web security.",
        source_type: "feed",
        default_config: %{
          "url" => "https://www.troyhunt.com/rss/",
          "interval" => 3_600_000
        },
        suggested_cluster: "Risk Assessment",
        kind: :stream
      },
      # Accessibility Review
      %__MODULE__{
        id: "accessibility_w3c_feed",
        banner: :tech,
        name: "W3C WAI Blog",
        description: "W3C Web Accessibility Initiative blog — guidelines updates, techniques, and best practices.",
        source_type: "feed",
        default_config: %{"url" => "https://www.w3.org/WAI/feed.xml", "interval" => 3_600_000},
        suggested_cluster: "Accessibility Review",
        kind: :stream
      },
      %__MODULE__{
        id: "accessibility_webaim_feed",
        banner: :tech,
        name: "WebAIM Blog",
        description: "WebAIM blog — practical accessibility articles, WCAG interpretation, and testing techniques.",
        source_type: "feed",
        default_config: %{"url" => "https://webaim.org/blog/feed", "interval" => 3_600_000},
        suggested_cluster: "Accessibility Review",
        kind: :stream
      },
      %__MODULE__{
        id: "accessibility_wcag_url",
        banner: :tech,
        name: "WCAG Spec Updates",
        description: "Watch the WCAG specification page for changes and updates.",
        source_type: "url",
        default_config: %{"url" => "https://www.w3.org/TR/WCAG22/", "interval" => 86_400_000},
        suggested_cluster: "Accessibility Review",
        kind: :stream
      },
      # Performance Audit
      %__MODULE__{
        id: "performance_flyio_feed",
        banner: :tech,
        name: "Fly.io Blog",
        description: "Fly.io engineering blog — deployment, infrastructure, and performance insights.",
        source_type: "feed",
        default_config: %{"url" => "https://fly.io/blog/feed.xml", "interval" => 3_600_000},
        suggested_cluster: "Performance Audit",
        kind: :stream
      },
      %__MODULE__{
        id: "performance_dashbit_feed",
        banner: :tech,
        name: "Dashbit Blog",
        description: "Dashbit blog — Elixir performance, Phoenix optimization, and ecosystem updates.",
        source_type: "feed",
        default_config: %{"url" => "https://dashbit.co/blog.atom", "interval" => 3_600_000},
        suggested_cluster: "Performance Audit",
        kind: :stream
      },
      %__MODULE__{
        id: "performance_phoenix_url",
        banner: :tech,
        name: "Phoenix Changelog",
        description: "Watch the Phoenix changelog for new releases and performance-related changes.",
        source_type: "url",
        default_config: %{
          "url" => "https://github.com/phoenixframework/phoenix/blob/main/CHANGELOG.md",
          "interval" => 86_400_000
        },
        suggested_cluster: "Performance Audit",
        kind: :stream
      },
      # Incident Triage
      %__MODULE__{
        id: "incident_hn_feed",
        banner: :tech,
        name: "HN Outage/Incident Feed",
        description: "Hacker News posts about outages, incidents, and postmortems.",
        source_type: "feed",
        default_config: %{
          "url" => "https://hnrss.org/newest?q=outage+OR+incident+OR+postmortem",
          "interval" => 1_800_000
        },
        suggested_cluster: "Incident Triage",
        kind: :stream
      },
      # Contract Review
      %__MODULE__{
        id: "contract_law_feed",
        banner: :business,
        name: "Law.com Legal News",
        description: "Law.com legal news feed — contract law updates and regulatory changes.",
        source_type: "feed",
        default_config: %{
          "url" => "https://feeds.law.com/law/LegalNews",
          "interval" => 3_600_000
        },
        suggested_cluster: "Contract Review",
        kind: :stream
      },
      # Dependency Audit
      %__MODULE__{
        id: "dependency_ghsa_feed",
        banner: :tech,
        name: "GitHub Advisory Database",
        description: "GitHub Security Advisory database feed — CVEs and vulnerability disclosures.",
        source_type: "feed",
        default_config: %{
          "url" => "https://github.com/advisories.atom",
          "interval" => 1_800_000
        },
        suggested_cluster: "Dependency Audit",
        kind: :stream
      },
      %__MODULE__{
        id: "dependency_elixir_security_feed",
        banner: :tech,
        name: "Elixir Security News",
        description: "Elixir Forum security category — Elixir/Erlang specific vulnerability announcements.",
        source_type: "feed",
        default_config: %{
          "url" => "https://elixirforum.com/c/elixir-news/security/55.rss",
          "interval" => 3_600_000
        },
        suggested_cluster: "Dependency Audit",
        kind: :stream
      },
      %__MODULE__{
        id: "dependency_hex_url",
        banner: :tech,
        name: "Hex.pm Package Updates",
        description: "Watch hex.pm for package updates relevant to your project.",
        source_type: "url",
        default_config: %{"url" => "https://hex.pm/packages", "interval" => 3_600_000},
        suggested_cluster: "Dependency Audit",
        kind: :stream
      },
      # General — no specific cluster
      %__MODULE__{
        id: "general_elixir_blog",
        name: "Elixir Lang Blog",
        description: "Official Elixir language blog — releases, announcements, and language updates.",
        source_type: "feed",
        default_config: %{
          "url" => "https://elixir-lang.org/blog.atom",
          "interval" => 86_400_000
        },
        suggested_cluster: nil,
        kind: :stream
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
        suggested_cluster: nil,
        kind: :stream
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
        suggested_cluster: nil,
        kind: :stream
      },
      # Tech
      %__MODULE__{
        id: "hacker_news_rss",
        banner: :tech,
        name: "Hacker News",
        description: "Top stories from Hacker News",
        source_type: "feed",
        default_config: %{"url" => "https://news.ycombinator.com/rss", "interval" => 1_800_000},
        suggested_cluster: "Tech Dispatch",
        kind: :stream
      },
      %__MODULE__{
        id: "the_verge_rss",
        banner: :tech,
        name: "The Verge",
        description: "Technology news and reviews from The Verge.",
        source_type: "feed",
        default_config: %{
          "url" => "https://www.theverge.com/rss/index.xml",
          "interval" => 1_800_000
        },
        suggested_cluster: "Tech Dispatch",
        kind: :stream
      },
      %__MODULE__{
        id: "ars_technica_rss",
        banner: :tech,
        name: "Ars Technica",
        description: "In-depth technology news and analysis from Ars Technica.",
        source_type: "feed",
        default_config: %{
          "url" => "https://feeds.arstechnica.com/arstechnica/index",
          "interval" => 1_800_000
        },
        suggested_cluster: "Tech Dispatch",
        kind: :stream
      },
      %__MODULE__{
        id: "techcrunch_rss",
        banner: :tech,
        name: "TechCrunch",
        description: "Startup and technology news from TechCrunch.",
        source_type: "feed",
        default_config: %{"url" => "https://techcrunch.com/feed/", "interval" => 1_800_000},
        suggested_cluster: "Tech Dispatch",
        kind: :stream
      },
      # Business
      %__MODULE__{
        id: "reuters_business_rss",
        banner: :business,
        name: "Reuters Business",
        description: "Business and financial news from Reuters.",
        source_type: "feed",
        default_config: %{
          "url" => "https://feeds.reuters.com/reuters/businessNews",
          "interval" => 1_800_000
        },
        suggested_cluster: "Market Signals",
        kind: :stream
      },
      %__MODULE__{
        id: "ft_rss",
        banner: :business,
        name: "Financial Times",
        description: "Global business and financial news from the Financial Times.",
        source_type: "feed",
        default_config: %{"url" => "https://www.ft.com/rss/home", "interval" => 1_800_000},
        suggested_cluster: "Market Signals",
        kind: :stream
      },
      # Sports
      %__MODULE__{
        id: "espn_rss",
        banner: :lifestyle,
        name: "ESPN",
        description: "Sports news and scores from ESPN.",
        source_type: "feed",
        default_config: %{
          "url" => "https://www.espn.com/espn/rss/news",
          "interval" => 1_800_000
        },
        suggested_cluster: "Sports Corner",
        kind: :stream
      },
      %__MODULE__{
        id: "bbc_sport_rss",
        banner: :lifestyle,
        name: "BBC Sport",
        description: "Sports news and results from BBC Sport.",
        source_type: "feed",
        default_config: %{
          "url" => "http://feeds.bbci.co.uk/sport/rss.xml",
          "interval" => 1_800_000
        },
        suggested_cluster: "Sports Corner",
        kind: :stream
      },
      %__MODULE__{
        id: "the_athletic_rss",
        banner: :lifestyle,
        name: "The Athletic",
        description: "In-depth sports journalism from The Athletic.",
        source_type: "feed",
        default_config: %{
          "url" => "https://theathletic.com/rss-feed/",
          "interval" => 1_800_000
        },
        suggested_cluster: "Sports Corner",
        kind: :stream
      },
      # Culture
      %__MODULE__{
        id: "pitchfork_rss",
        banner: :lifestyle,
        name: "Pitchfork",
        description: "Music news and reviews from Pitchfork.",
        source_type: "feed",
        default_config: %{
          "url" => "https://pitchfork.com/rss/news/",
          "interval" => 3_600_000
        },
        suggested_cluster: "Culture Desk",
        kind: :stream
      },
      %__MODULE__{
        id: "av_club_rss",
        banner: :lifestyle,
        name: "AV Club",
        description: "Pop culture and entertainment reviews from The AV Club.",
        source_type: "feed",
        default_config: %{"url" => "https://www.avclub.com/rss", "interval" => 3_600_000},
        suggested_cluster: "Culture Desk",
        kind: :stream
      },
      %__MODULE__{
        id: "vulture_rss",
        banner: :lifestyle,
        name: "Vulture",
        description: "Entertainment and culture coverage from Vulture.",
        source_type: "feed",
        default_config: %{
          "url" => "https://www.vulture.com/rss/all.xml",
          "interval" => 3_600_000
        },
        suggested_cluster: "Culture Desk",
        kind: :stream
      },
      # Science
      %__MODULE__{
        id: "science_daily_rss",
        banner: :lifestyle,
        name: "Science Daily",
        description: "Breaking science news from ScienceDaily.",
        source_type: "feed",
        default_config: %{
          "url" => "https://www.sciencedaily.com/rss/all.xml",
          "interval" => 3_600_000
        },
        suggested_cluster: "Science Watch",
        kind: :stream
      },
      %__MODULE__{
        id: "nature_news_rss",
        banner: :lifestyle,
        name: "Nature News",
        description: "Science news and research from Nature.",
        source_type: "feed",
        default_config: %{"url" => "https://www.nature.com/nature.rss", "interval" => 3_600_000},
        suggested_cluster: "Science Watch",
        kind: :stream
      },
      %__MODULE__{
        id: "ars_science_rss",
        banner: :lifestyle,
        name: "Ars Technica Science",
        description: "Science and technology research coverage from Ars Technica.",
        source_type: "feed",
        default_config: %{
          "url" => "https://feeds.arstechnica.com/arstechnica/science",
          "interval" => 3_600_000
        },
        suggested_cluster: "Science Watch",
        kind: :stream
      }
    ]
  end

  def filter_by_banner(banner) do
    Enum.filter(all(), &(&1.banner == banner || &1.banner == nil))
  end

  def get(id), do: Enum.find(all(), &(&1.id == id))
  def for_cluster(cluster_name), do: Enum.filter(all(), &(&1.suggested_cluster == cluster_name))

  def for_banner(banner) when is_atom(banner) do
    Enum.filter(streams(), &(&1.banner == banner))
  end
end
