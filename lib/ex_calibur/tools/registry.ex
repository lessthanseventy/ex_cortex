defmodule ExCalibur.Tools.Registry do
  @moduledoc """
  Registry of available tools, tiered by safety.

  Returns `ReqLLM.Tool` structs — pass them directly to
  `ReqLLM.generate_text(model, context, tools: tools)`.

  Tiers:
  - safe      — read-only, low risk (query_lore, fetch_url)
  - write     — write or mutate data (none yet)
  - dangerous — execute code/pipelines (run_quest)

  Usage:
    Registry.list_safe()              # safe tools only
    Registry.list_write()             # safe + write tools
    Registry.list_dangerous()         # all tools
    Registry.get("query_lore")        # single tool by name
    Registry.resolve_tools(:all_safe) # from step/member config
  """

  alias ExCalibur.Tools.{
    QueryLore,
    FetchUrl,
    RunQuest,
    SearchObsidian,
    SearchObsidianContent,
    ReadObsidian,
    ReadObsidianFrontmatter,
    CreateObsidianNote,
    DailyObsidian,
    SearchEmail,
    ReadEmail,
    SendEmail,
    SearchGithub,
    ReadGithubIssue,
    ListGithubNotifications,
    CreateGithubIssue,
    CommentGithub
  }

  @safe [
    QueryLore,
    FetchUrl,
    SearchObsidian,
    SearchObsidianContent,
    ReadObsidian,
    ReadObsidianFrontmatter,
    SearchEmail,
    ReadEmail,
    SearchGithub,
    ReadGithubIssue,
    ListGithubNotifications
  ]
  @write [CreateObsidianNote, DailyObsidian]
  @dangerous [RunQuest, SendEmail, CreateGithubIssue, CommentGithub]

  def list_safe, do: Enum.map(@safe, & &1.req_llm_tool())
  def list_write, do: Enum.map(@safe ++ @write, & &1.req_llm_tool())
  def list_dangerous, do: Enum.map(@safe ++ @write ++ @dangerous, & &1.req_llm_tool())

  def resolve_tools(:all_safe), do: list_safe()
  def resolve_tools(:write), do: list_write()
  def resolve_tools(:dangerous), do: list_dangerous()
  def resolve_tools(:yolo), do: list_dangerous()

  def resolve_tools(names) when is_list(names) do
    all = list_dangerous()
    Enum.filter(all, &(&1.name in names))
  end

  def get(name) when is_binary(name) do
    Enum.find(list_dangerous(), &(&1.name == name))
  end
end
