defmodule ExCortex.ContextProviders.Signals do
  @moduledoc """
  Injects recent dashboard signal cards as prompt context.

  Config options:
    "limit" - max signals (default 5)
    "status" - filter by status (default "active")
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  import Ecto.Query

  alias ExCortex.Repo
  alias ExCortex.Signals.Signal

  @impl true
  def build(config, _thought, input) do
    limit = Map.get(config, "limit", 5)
    status = Map.get(config, "status", "active")

    signals =
      Repo.all(from(s in Signal, where: s.status == ^status, order_by: [desc: s.inserted_at], limit: 20))

    scored = score_and_rank(signals, input, limit)

    if scored == [] do
      ""
    else
      entries =
        Enum.map(scored, fn s ->
          age = format_age(s.inserted_at)
          body = String.slice(s.body || "", 0, 2000)
          tags = if s.tags == [], do: "", else: " [#{Enum.join(s.tags, ", ")}]"
          "### #{s.title}#{tags}\n*#{age} · #{s.source || "system"}*\n\n#{body}"
        end)

      "## Dashboard Signals\n\n" <> Enum.join(entries, "\n\n---\n\n")
    end
  end

  defp score_and_rank(signals, input, limit) do
    question_words =
      input
      |> String.downcase()
      |> String.split(~r/\W+/, trim: true)
      |> MapSet.new()

    signals
    |> Enum.map(fn s ->
      signal_words =
        "#{s.title} #{Enum.join(s.tags || [], " ")}"
        |> String.downcase()
        |> String.split(~r/\W+/, trim: true)
        |> MapSet.new()

      overlap = question_words |> MapSet.intersection(signal_words) |> MapSet.size()
      {s, overlap}
    end)
    |> Enum.sort_by(fn {_s, score} -> score end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {s, _score} -> s end)
  end

  defp format_age(nil), do: "unknown"

  defp format_age(inserted_at) do
    utc =
      if is_struct(inserted_at, NaiveDateTime),
        do: DateTime.from_naive!(inserted_at, "Etc/UTC"),
        else: inserted_at

    diff = DateTime.diff(DateTime.utc_now(), utc, :minute)

    cond do
      diff < 60 -> "#{diff}m ago"
      diff < 1440 -> "#{div(diff, 60)}h ago"
      true -> "#{div(diff, 1440)}d ago"
    end
  end
end
