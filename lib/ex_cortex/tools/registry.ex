defmodule ExCortex.Tools.Registry do
  @moduledoc """
  Registry of available tools, tiered by safety.

  Returns `ReqLLM.Tool` structs — pass them directly to
  `ReqLLM.generate_text(model, context, tools: tools)`.

  Tiers:
  - safe      — read-only, low risk (query_memory, query_axiom, fetch_url, obsidian read, email read, github read, jq, pdf, document conversion)
  - write     — write or mutate data (create_obsidian_note, daily_obsidian)
  - dangerous — execute code/pipelines or send data externally (run_rumination, send_email, create_github_issue, comment_github)

  Usage:
    Registry.list_safe()              # safe tools only
    Registry.list_write()             # safe + write tools
    Registry.list_dangerous()         # all tools
    Registry.get("query_memory")      # single tool by name
    Registry.resolve_tools(:all_safe) # from step/neuron config
  """

  alias ExCortex.Tools.AnalyzeVideo
  alias ExCortex.Tools.CloseIssue
  alias ExCortex.Tools.CommentGithub
  alias ExCortex.Tools.ConvertDocument
  alias ExCortex.Tools.CreateGithubIssue
  alias ExCortex.Tools.CreateNextcloudNote
  alias ExCortex.Tools.CreateObsidianNote
  alias ExCortex.Tools.DailyObsidian
  alias ExCortex.Tools.DescribeImage
  alias ExCortex.Tools.DownloadMedia
  alias ExCortex.Tools.EditFile
  alias ExCortex.Tools.EmailClassify
  alias ExCortex.Tools.EmailMove
  alias ExCortex.Tools.EmailTag
  alias ExCortex.Tools.ExtractAudio
  alias ExCortex.Tools.ExtractFrames
  alias ExCortex.Tools.FetchUrl
  alias ExCortex.Tools.GitCommit
  alias ExCortex.Tools.GitPull
  alias ExCortex.Tools.GitPush
  alias ExCortex.Tools.JqQuery
  alias ExCortex.Tools.ListFiles
  alias ExCortex.Tools.ListGithubNotifications
  alias ExCortex.Tools.ListSources
  alias ExCortex.Tools.MergePR
  alias ExCortex.Tools.NextcloudCalendar
  alias ExCortex.Tools.NextcloudTalk
  alias ExCortex.Tools.OpenPR
  alias ExCortex.Tools.QueryAxiom
  alias ExCortex.Tools.QueryJaeger
  alias ExCortex.Tools.QueryMemory
  alias ExCortex.Tools.ReadEmail
  alias ExCortex.Tools.ReadFile
  alias ExCortex.Tools.ReadGithubIssue
  alias ExCortex.Tools.ReadImageText
  alias ExCortex.Tools.ReadNextcloud
  alias ExCortex.Tools.ReadNextcloudNotes
  alias ExCortex.Tools.ReadObsidian
  alias ExCortex.Tools.ReadObsidianFrontmatter
  alias ExCortex.Tools.ReadPdf
  alias ExCortex.Tools.RestartApp
  alias ExCortex.Tools.RunRumination
  alias ExCortex.Tools.RunSandbox
  alias ExCortex.Tools.SearchEmail
  alias ExCortex.Tools.SearchGithub
  alias ExCortex.Tools.SearchNextcloud
  alias ExCortex.Tools.SearchObsidian
  alias ExCortex.Tools.SearchObsidianContent
  alias ExCortex.Tools.SendEmail
  alias ExCortex.Tools.SetupWorktree
  alias ExCortex.Tools.TranscribeAudio
  alias ExCortex.Tools.WebFetch
  alias ExCortex.Tools.WebSearch
  alias ExCortex.Tools.WriteFile
  alias ExCortex.Tools.WriteNextcloud

  @safe [
    QueryMemory,
    QueryAxiom,
    QueryJaeger,
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
    AnalyzeVideo,
    ReadFile,
    ListFiles,
    RunSandbox,
    SearchNextcloud,
    ReadNextcloud,
    ReadNextcloudNotes,
    ListSources
  ]
  @write [
    CreateObsidianNote,
    DailyObsidian,
    DownloadMedia,
    ExtractAudio,
    ExtractFrames,
    SetupWorktree,
    WriteFile,
    EditFile,
    GitCommit,
    GitPush,
    OpenPR,
    WriteNextcloud,
    CreateNextcloudNote,
    NextcloudCalendar
  ]
  @dangerous [
    RunRumination,
    SendEmail,
    CreateGithubIssue,
    CommentGithub,
    MergePR,
    GitPull,
    RestartApp,
    CloseIssue,
    NextcloudTalk,
    EmailClassify,
    EmailTag,
    EmailMove
  ]

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
