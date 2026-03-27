defmodule ExCortex.Memory.ConversationSummarizer do
  @moduledoc """
  Generates conversational engrams from completed Muse/Wonder sessions.
  Subscribes to thought completions, groups by session window, and
  creates a summary engram when the session closes.
  """
  use GenServer

  alias ExCortex.Memory
  alias ExCortex.Memory.TierGenerator

  require Logger

  @session_timeout_ms 30 * 60 * 1_000
  @min_exchanges 3

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def should_summarize?(thoughts) when is_list(thoughts), do: length(thoughts) >= @min_exchanges

  def build_transcript(thoughts) do
    thoughts
    |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
    |> Enum.map_join("\n\n", fn t ->
      "**Q:** #{t.question}\n**A:** #{t.answer}"
    end)
  end

  def compute_importance(exchange_count) when exchange_count >= 8, do: 4
  def compute_importance(exchange_count) when exchange_count >= 5, do: 3
  def compute_importance(_), do: 2

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "thoughts")
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_info({:thought_created, thought}, state) do
    session_key = {thought.scope, session_bucket(thought.inserted_at)}
    sessions = state.sessions

    session = Map.get(sessions, session_key, [])
    updated_session = [thought | session]
    sessions = Map.put(sessions, session_key, updated_session)

    schedule_session_close(session_key)

    {:noreply, %{state | sessions: sessions}}
  end

  def handle_info({:session_timeout, session_key}, state) do
    {thoughts, sessions} = Map.pop(state.sessions, session_key, [])

    if should_summarize?(thoughts) do
      Task.Supervisor.start_child(ExCortex.AsyncTaskSupervisor, fn ->
        create_conversational_engram(thoughts, session_key)
      end)
    end

    {:noreply, %{state | sessions: sessions}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp create_conversational_engram(thoughts, {scope, _bucket}) do
    transcript = build_transcript(thoughts)
    thought_ids = thoughts |> Enum.map(& &1.id) |> Enum.sort()
    dedup_tag = "session-#{:erlang.phash2(thought_ids)}"

    existing = Memory.list_engrams(tags: [dedup_tag])

    if existing == [] do
      title = title_from_thoughts(thoughts)

      case Memory.create_engram(%{
             title: title,
             body: transcript,
             category: "conversational",
             source: scope,
             importance: compute_importance(length(thoughts)),
             tags: ["conversational", dedup_tag]
           }) do
        {:ok, engram} ->
          TierGenerator.generate_async(engram)
          Logger.info("[ConversationSummarizer] Created conversational engram: #{title}")

        {:error, reason} ->
          Logger.warning("[ConversationSummarizer] Failed to create engram: #{inspect(reason)}")
      end
    end
  end

  defp title_from_thoughts(thoughts) do
    first_q = List.last(thoughts).question
    truncated = String.slice(first_q, 0, 80)
    count = length(thoughts)
    "Conversation: #{truncated} (#{count} exchanges)"
  end

  defp session_bucket(naive_datetime) do
    minutes = naive_datetime.minute
    bucket = div(minutes, 30) * 30
    {naive_datetime.year, naive_datetime.month, naive_datetime.day, naive_datetime.hour, bucket}
  end

  defp schedule_session_close(session_key) do
    Process.send_after(self(), {:session_timeout, session_key}, @session_timeout_ms)
  end
end
