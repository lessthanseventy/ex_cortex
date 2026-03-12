defmodule ExCalibur.Tools.Registry do
  @moduledoc """
  Registry of available tools, tiered by safety.

  Returns `ReqLLM.Tool` structs — pass them directly to
  `ReqLLM.generate_text(model, context, tools: tools)`.

  Tiers:
  - safe      — read-only, low risk (query_lore, query_dictionary, fetch_url, obsidian read, email read, github read, jq, pdf, document conversion)
  - write     — write or mutate data (create_obsidian_note, daily_obsidian)
  - dangerous — execute code/pipelines or send data externally (run_quest, send_email, create_github_issue, comment_github)

  Usage:
    Registry.list_safe()              # safe tools only
    Registry.list_write()             # safe + write tools
    Registry.list_dangerous()         # all tools
    Registry.get("query_lore")        # single tool by name
    Registry.resolve_tools(:all_safe) # from step/member config
  """

  alias ExCalibur.Tools.AnalyzeVideo
  alias ExCalibur.Tools.CommentGithub
  alias ExCalibur.Tools.ConvertDocument
  alias ExCalibur.Tools.CreateGithubIssue
  alias ExCalibur.Tools.CreateObsidianNote
  alias ExCalibur.Tools.DailyObsidian
  alias ExCalibur.Tools.DescribeImage
  alias ExCalibur.Tools.DownloadMedia
  alias ExCalibur.Tools.ExtractAudio
  alias ExCalibur.Tools.ExtractFrames
  alias ExCalibur.Tools.FetchUrl
  alias ExCalibur.Tools.JqQuery
  alias ExCalibur.Tools.ListGithubNotifications
  alias ExCalibur.Tools.QueryDictionary
  alias ExCalibur.Tools.QueryLore
  alias ExCalibur.Tools.ReadEmail
  alias ExCalibur.Tools.ReadGithubIssue
  alias ExCalibur.Tools.ReadImageText
  alias ExCalibur.Tools.ReadObsidian
  alias ExCalibur.Tools.ReadObsidianFrontmatter
  alias ExCalibur.Tools.ReadPdf
  alias ExCalibur.Tools.RunQuest
  alias ExCalibur.Tools.SearchEmail
  alias ExCalibur.Tools.SearchGithub
  alias ExCalibur.Tools.SearchObsidian
  alias ExCalibur.Tools.SearchObsidianContent
  alias ExCalibur.Tools.SendEmail
  alias ExCalibur.Tools.TranscribeAudio
  alias ExCalibur.Tools.WebFetch
  alias ExCalibur.Tools.WebSearch

  @safe [
    QueryLore,
    QueryDictionary,
    FetchUrl,
    SearchObsidian,
    SearchObsidianContent,
    ReadObsidian,
    ReadObsidianFrontmatter,
    SearchEmail,
    ReadEmail,
    SearchGithub,
    ReadGithubIssue,
    ListGithubNotifications,
    JqQuery,
    ReadPdf,
    ConvertDocument,
    WebFetch,
    WebSearch,
    TranscribeAudio,
    DescribeImage,
    ReadImageText,
    AnalyzeVideo
  ]
  @write [CreateObsidianNote, DailyObsidian, DownloadMedia, ExtractAudio, ExtractFrames]
  @dangerous [RunQuest, SendEmail, CreateGithubIssue, CommentGithub]

  def list_safe, do: Enum.map(@safe, & &1.req_llm_tool())
  def list_write, do: Enum.map(@safe ++ @write, & &1.req_llm_tool())
  def list_dangerous, do: Enum.map(@safe ++ @write ++ @dangerous, & &1.req_llm_tool())

  def resolve_tools(nil), do: []
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
