defmodule ExCortexTUI.Screens.Proposals do
  @moduledoc "Proposal review screen: list, expand, approve/reject pending proposals."

  @behaviour ExCortexTUI.Screen

  @impl true
  def init(_opts) do
    %{proposals: fetch_proposals(), cursor: 0, expanded: nil}
  end

  @impl true
  def render(state) do
    content =
      if Enum.empty?(state.proposals) do
        Owl.Data.tag("  No pending proposals", :yellow)
      else
        state.proposals
        |> Enum.with_index()
        |> Enum.map_intersperse("\n", &render_proposal_row(&1, state.expanded, state.cursor))
      end

    hints = [
      "\n",
      Owl.Data.tag("[j/k]", :cyan),
      " navigate  ",
      Owl.Data.tag("[enter/space]", :cyan),
      " expand  ",
      Owl.Data.tag("[y]", :cyan),
      " approve  ",
      Owl.Data.tag("[n]", :cyan),
      " reject  ",
      Owl.Data.tag("[r]", :cyan),
      " refresh  ",
      Owl.Data.tag("[esc]", :cyan),
      " back"
    ]

    [
      Owl.Box.new(content, title: "Proposals (#{length(state.proposals)} pending)", min_width: 64),
      "\n" | hints
    ]
  end

  @impl true
  def handle_key(key, state) when key in ["j", "\e[B"] do
    max = max(length(state.proposals) - 1, 0)
    {:noreply, %{state | cursor: min(state.cursor + 1, max)}}
  end

  def handle_key(key, state) when key in ["k", "\e[A"] do
    {:noreply, %{state | cursor: max(state.cursor - 1, 0)}}
  end

  def handle_key(key, state) when key in ["\r", " "] do
    expanded =
      if state.expanded == state.cursor do
        nil
      else
        state.cursor
      end

    {:noreply, %{state | expanded: expanded}}
  end

  def handle_key("y", state) do
    case Enum.at(state.proposals, state.cursor) do
      nil ->
        {:noreply, state}

      proposal ->
        ExCortex.Ruminations.approve_proposal(proposal)
        proposals = fetch_proposals()
        cursor = min(state.cursor, max(length(proposals) - 1, 0))
        {:noreply, %{state | proposals: proposals, cursor: cursor, expanded: nil}}
    end
  rescue
    _ -> {:noreply, state}
  end

  def handle_key("n", state) do
    case Enum.at(state.proposals, state.cursor) do
      nil ->
        {:noreply, state}

      proposal ->
        ExCortex.Ruminations.reject_proposal(proposal)
        proposals = fetch_proposals()
        cursor = min(state.cursor, max(length(proposals) - 1, 0))
        {:noreply, %{state | proposals: proposals, cursor: cursor, expanded: nil}}
    end
  rescue
    _ -> {:noreply, state}
  end

  def handle_key("s", state) do
    max = max(length(state.proposals) - 1, 0)
    {:noreply, %{state | cursor: min(state.cursor + 1, max)}}
  end

  def handle_key("r", state) do
    {:noreply, %{state | proposals: fetch_proposals()}}
  end

  def handle_key(_key, state), do: {:noreply, state}

  # -- Rendering --

  defp render_proposal_row({proposal, idx}, expanded, cursor) do
    if expanded == idx do
      render_expanded(proposal, idx, idx == cursor)
    else
      render_collapsed(proposal, idx, idx == cursor)
    end
  end

  defp render_collapsed(proposal, _idx, selected) do
    prefix = if selected, do: Owl.Data.tag("▸ ", [:bright, :cyan]), else: "  "
    type_color = type_color(proposal.type)
    confidence = get_confidence(proposal)
    age = relative_time(proposal.inserted_at)

    [
      prefix,
      Owl.Data.tag("[#{proposal.type || "?"}]", type_color),
      "  ",
      truncate(proposal.description || "(no description)", 36),
      "  ",
      Owl.Data.tag("#{confidence}", :yellow),
      "  ",
      Owl.Data.tag(age, :faint)
    ]
  end

  defp render_expanded(proposal, _idx, selected) do
    prefix = if selected, do: Owl.Data.tag("▾ ", [:bright, :cyan]), else: "  "
    type_color = type_color(proposal.type)
    confidence = get_confidence(proposal)
    age = relative_time(proposal.inserted_at)

    header = [
      prefix,
      Owl.Data.tag("[#{proposal.type || "?"}]", type_color),
      "  ",
      truncate(proposal.description || "(no description)", 36),
      "  ",
      Owl.Data.tag("#{confidence}", :yellow),
      "  ",
      Owl.Data.tag(age, :faint)
    ]

    details = proposal.details || %{}

    detail_lines =
      [
        {"Description", proposal.description},
        {"Type", proposal.type},
        {"Confidence", confidence},
        {"Context", proposal.context},
        {"Reason", details["reason"] || details["rationale"]}
      ]
      |> Enum.reject(fn {_label, val} -> is_nil(val) or val == "" end)
      |> Enum.map(fn {label, val} ->
        ["    ", Owl.Data.tag("#{label}: ", :faint), truncate(to_string(val), 48)]
      end)

    action_hint = [
      "    ",
      Owl.Data.tag("[y]", :green),
      " approve  ",
      Owl.Data.tag("[n]", :red),
      " reject  ",
      Owl.Data.tag("[s]", :faint),
      " skip"
    ]

    [header, "\n"] ++ Enum.intersperse(detail_lines ++ [action_hint], "\n")
  end

  # -- Data fetching --

  defp fetch_proposals do
    ExCortex.Ruminations.list_proposals(status: "pending")
  rescue
    _ -> []
  end

  # -- Helpers --

  defp get_confidence(%{details: %{"confidence" => c}}) when is_number(c), do: "#{round(c * 100)}%"

  defp get_confidence(%{details: %{"confidence" => c}}) when is_binary(c), do: c
  defp get_confidence(_), do: "—"

  defp type_color("roster_change"), do: :cyan
  defp type_color("schedule_change"), do: :green
  defp type_color("prompt_change"), do: :yellow
  defp type_color("tool_action"), do: :red
  defp type_color(_), do: :faint

  defp relative_time(nil), do: "?"

  defp relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp relative_time(%NaiveDateTime{} = dt), do: dt |> DateTime.from_naive!("Etc/UTC") |> relative_time()
  defp relative_time(_), do: "?"

  defp truncate(nil, _max), do: ""
  defp truncate(s, max) when byte_size(s) <= max, do: s
  defp truncate(s, max), do: String.slice(s, 0, max - 1) <> "…"
end
