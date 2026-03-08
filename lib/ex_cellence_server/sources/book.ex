defmodule ExCellenceServer.Sources.Book do
  @moduledoc false
  defstruct [:id, :name, :description, :source_type, :default_config, :suggested_guild]

  def all do
    [
      %__MODULE__{
        id: "git_repo_watcher",
        name: "Git Repo Watcher",
        description: "Watch a local git repository for new commits and generate diffs for review.",
        source_type: "git",
        default_config: %{"repo_path" => "", "branch" => "main", "interval" => 60_000},
        suggested_guild: "Code Review"
      },
      %__MODULE__{
        id: "directory_watcher",
        name: "Directory Watcher",
        description: "Monitor a directory for new or changed files.",
        source_type: "directory",
        default_config: %{"path" => "", "patterns" => ["*.txt", "*.md"], "interval" => 30_000},
        suggested_guild: "Content Moderation"
      },
      %__MODULE__{
        id: "rss_feed",
        name: "RSS/Atom Feed",
        description: "Poll an RSS or Atom feed for new entries.",
        source_type: "feed",
        default_config: %{"url" => "", "interval" => 300_000},
        suggested_guild: "Risk Assessment"
      },
      %__MODULE__{
        id: "webhook_receiver",
        name: "Webhook Receiver",
        description: "Expose a POST endpoint that accepts data pushes. Supports optional Bearer token auth.",
        source_type: "webhook",
        default_config: %{},
        suggested_guild: nil
      },
      %__MODULE__{
        id: "url_watcher",
        name: "URL Watcher",
        description: "Periodically fetch a URL and detect content changes.",
        source_type: "url",
        default_config: %{"url" => "", "interval" => 60_000},
        suggested_guild: nil
      },
      %__MODULE__{
        id: "websocket_stream",
        name: "WebSocket Stream",
        description: "Connect to a WebSocket endpoint and process incoming messages.",
        source_type: "websocket",
        default_config: %{"url" => "", "message_path" => "", "interval" => 60_000},
        suggested_guild: nil
      }
    ]
  end

  def get(id), do: Enum.find(all(), &(&1.id == id))
  def for_guild(guild_name), do: Enum.filter(all(), &(&1.suggested_guild == guild_name))
end
