defmodule ExCortex.Ruminations.KeywordTriggerRunner do
  @moduledoc """
  Listens for signals, engrams, and sense items and fires any ruminations
  with trigger: "keyword" whose keyword_patterns match the content.
  """
  use GenServer

  import Ecto.Query

  alias ExCortex.Repo
  alias ExCortex.Ruminations.Rumination
  alias ExCortex.Ruminations.Runner

  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "cortex")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "engram_triggers")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "senses")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "ruminations")
    ruminations = load_keyword_ruminations()
    {:ok, %{ruminations: ruminations}}
  end

  @impl true
  def handle_info({:signal_posted, signal}, state) do
    content = [signal[:body], signal[:title]] |> Enum.filter(&is_binary/1) |> Enum.join(" ")
    fire_matches(content, state.ruminations)
    {:noreply, state}
  end

  def handle_info({:engram_created, engram}, state) do
    content = [engram[:body], engram[:impression]] |> Enum.filter(&is_binary/1) |> Enum.join(" ")
    fire_matches(content, state.ruminations)
    {:noreply, state}
  end

  def handle_info({:sense_item, item}, state) do
    content = item[:content] || ""
    fire_matches(content, state.ruminations)
    {:noreply, state}
  end

  def handle_info({:rumination_updated, _}, state) do
    {:noreply, %{state | ruminations: load_keyword_ruminations()}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ────────────────────────────────────────────────────────────────

  defp load_keyword_ruminations do
    Repo.all(
      from r in Rumination,
        where: r.trigger == "keyword" and r.status == "active"
    )
  rescue
    e in DBConnection.OwnershipError ->
      _ = e
      []

    e ->
      Logger.warning("[KeywordTriggerRunner] Failed to load ruminations: #{inspect(e)}")
      []
  end

  defp fire_matches(_content, []), do: :ok

  defp fire_matches(content, ruminations) do
    content_lower = String.downcase(content)
    Enum.each(ruminations, &maybe_fire(&1, content, content_lower))
  end

  defp maybe_fire(rumination, content, content_lower) do
    if patterns_match?(rumination.keyword_patterns, content_lower) do
      Logger.info("[KeywordTriggerRunner] Firing rumination #{rumination.id} (#{rumination.name}) on keyword match")

      Task.start(fn -> Runner.run(rumination, content) end)
    end
  end

  defp patterns_match?([], _content_lower), do: false

  defp patterns_match?(patterns, content_lower) do
    Enum.any?(patterns, fn pattern ->
      String.contains?(content_lower, String.downcase(pattern))
    end)
  end
end
