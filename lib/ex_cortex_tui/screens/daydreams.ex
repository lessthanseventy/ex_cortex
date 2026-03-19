defmodule ExCortexTUI.Screens.Daydreams do
  @moduledoc "Daydream list and tail screen: browse recent daydreams, tail a running one."

  @behaviour ExCortexTUI.Screen

  import Ecto.Query

  alias ExCortex.Repo
  alias ExCortex.Ruminations.Daydream
  alias ExCortex.Ruminations.Impulse
  alias ExCortex.Ruminations.Rumination

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")
    %{mode: :list, daydreams: fetch_daydreams(), cursor: 0}
  end

  @impl true
  def render(%{mode: :list} = state), do: render_list(state)
  def render(%{mode: :tail} = state), do: render_tail(state)

  @impl true
  def handle_key(key, %{mode: :list} = state), do: handle_list_key(key, state)
  def handle_key(key, %{mode: :tail} = state), do: handle_tail_key(key, state)

  @impl true
  def handle_info({:step_completed, %{daydream_id: id} = step_data}, %{mode: :tail, daydream: d} = state) do
    if d.id == id do
      steps = state.steps ++ [step_data]
      {:noreply, %{state | steps: steps}}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, %{mode: :list} = state) do
    {:noreply, %{state | daydreams: fetch_daydreams()}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -- List mode --

  defp handle_list_key(key, state) when key in ["j", "\e[B"] do
    max = max(length(state.daydreams) - 1, 0)
    {:noreply, %{state | cursor: min(state.cursor + 1, max)}}
  end

  defp handle_list_key(key, state) when key in ["k", "\e[A"] do
    {:noreply, %{state | cursor: max(state.cursor - 1, 0)}}
  end

  defp handle_list_key("\r", state) do
    case Enum.at(state.daydreams, state.cursor) do
      nil ->
        {:noreply, state}

      {daydream, _name} ->
        impulses = fetch_impulses(daydream.id)
        {:noreply, %{state | mode: :tail, daydream: daydream, steps: impulses}}
    end
  end

  defp handle_list_key("r", state) do
    {:noreply, %{state | daydreams: fetch_daydreams()}}
  end

  defp handle_list_key(_key, state), do: {:noreply, state}

  defp render_list(state) do
    daydreams = state.daydreams

    content =
      if Enum.empty?(daydreams) do
        Owl.Data.tag("  No daydreams found", :yellow)
      else
        header = [
          Owl.Data.tag(
            "  #{String.pad_trailing("STATUS", 8)}  #{String.pad_trailing("RUMINATION", 24)}  #{String.pad_trailing("STEPS", 8)}  AGE",
            :faint
          )
        ]

        divider = [Owl.Data.tag("  #{String.duplicate("─", 58)}", :faint)]

        rows =
          daydreams
          |> Enum.with_index()
          |> Enum.map(fn {{daydream, rum_name}, idx} ->
            selected = idx == state.cursor
            dot_color = status_color(daydream.status)
            name = truncate(rum_name || "##{daydream.rumination_id}", 24)
            step_count = map_size(daydream.synapse_results || %{})
            age = relative_time(daydream.inserted_at)

            line = [
              if(selected, do: Owl.Data.tag("▸ ", [:bright, :cyan]), else: "  "),
              Owl.Data.tag("● ", dot_color),
              String.pad_trailing(daydream.status || "?", 6),
              "  ",
              String.pad_trailing(name, 24),
              "  ",
              String.pad_trailing("#{step_count}", 8),
              "  ",
              Owl.Data.tag(age, :faint)
            ]

            if selected do
              [Owl.Data.tag("", [:bright, :cyan]) | line]
            else
              line
            end
          end)

        header ++ divider ++ Enum.intersperse(rows, "\n")
      end

    hints = [
      "\n",
      Owl.Data.tag("[j/k]", :cyan),
      " navigate  ",
      Owl.Data.tag("[enter]", :cyan),
      " tail  ",
      Owl.Data.tag("[r]", :cyan),
      " refresh  ",
      Owl.Data.tag("[esc]", :cyan),
      " back"
    ]

    [
      Owl.Box.new(content, title: "Daydreams", min_width: 64),
      "\n" | hints
    ]
  end

  # -- Tail mode --

  defp handle_tail_key("\e", state) do
    {:noreply, %{state | mode: :list, daydreams: fetch_daydreams()}}
  end

  defp handle_tail_key("r", state) do
    impulses = fetch_impulses(state.daydream.id)
    {:noreply, %{state | steps: impulses}}
  end

  defp handle_tail_key(_key, state), do: {:noreply, state}

  defp render_tail(state) do
    daydream = state.daydream

    header_line = [
      Owl.Data.tag("Daydream ##{daydream.id}", [:bright, :cyan]),
      "  ",
      Owl.Data.tag("● ", status_color(daydream.status)),
      daydream.status || "?"
    ]

    steps_content =
      if Enum.empty?(state.steps) do
        [Owl.Data.tag("  No impulses yet", :yellow)]
      else
        Enum.map(state.steps, fn step ->
          render_step_line(step)
        end)
      end

    content = [header_line, "\n", Owl.Data.tag(String.duplicate("─", 56), :faint), "\n" | steps_content]

    hints = [
      "\n",
      Owl.Data.tag("[esc]", :cyan),
      " back to list  ",
      Owl.Data.tag("[r]", :cyan),
      " refresh"
    ]

    [
      Owl.Box.new(content, title: "Daydream Tail", min_width: 64),
      "\n" | hints
    ]
  end

  defp render_step_line(%Impulse{} = impulse) do
    color = status_color(impulse.status)
    duration = format_duration(impulse)
    verdict = extract_verdict(impulse.results)

    [
      Owl.Data.tag("  ● ", color),
      "Step ##{impulse.synapse_id}",
      "  ",
      Owl.Data.tag("[#{impulse.status}]", color),
      if(verdict, do: ["  ", Owl.Data.tag(verdict, verdict_color(verdict))], else: []),
      if(duration, do: Owl.Data.tag("  #{duration}", :faint), else: [])
    ]
  end

  defp render_step_line(%{step_name: name, status: status} = step) do
    color = status_color(status)
    duration = if step[:duration_ms], do: "#{step.duration_ms}ms"
    preview = truncate(step[:output_preview] || "", 40)

    [
      Owl.Data.tag("  ● ", color),
      truncate(name || "step", 20),
      "  ",
      Owl.Data.tag("[#{status}]", color),
      if(preview == "", do: [], else: ["  ", preview]),
      if(duration, do: Owl.Data.tag("  #{duration}", :faint), else: [])
    ]
  end

  defp render_step_line(_step), do: Owl.Data.tag("  ● unknown step", :faint)

  # -- Data fetching --

  defp fetch_daydreams do
    daydreams =
      Repo.all(
        from(d in Daydream,
          order_by: [desc: d.inserted_at],
          limit: 20
        )
      )

    rum_ids = daydreams |> Enum.map(& &1.rumination_id) |> Enum.uniq()

    rum_names =
      if Enum.empty?(rum_ids) do
        %{}
      else
        from(r in Rumination, where: r.id in ^rum_ids, select: {r.id, r.name})
        |> Repo.all()
        |> Map.new()
      end

    Enum.map(daydreams, fn d ->
      {d, Map.get(rum_names, d.rumination_id, "?")}
    end)
  rescue
    _ -> []
  end

  defp fetch_impulses(daydream_id) do
    Repo.all(
      from(i in Impulse,
        where: i.daydream_id == ^daydream_id,
        order_by: [asc: i.inserted_at]
      )
    )
  rescue
    _ -> []
  end

  # -- Helpers --

  defp status_color("complete"), do: :green
  defp status_color("pass"), do: :green
  defp status_color("failed"), do: :red
  defp status_color("fail"), do: :red
  defp status_color("running"), do: :cyan
  defp status_color("pending"), do: :yellow
  defp status_color(_), do: :yellow

  defp verdict_color("pass"), do: :green
  defp verdict_color("fail"), do: :red
  defp verdict_color(_), do: :yellow

  defp extract_verdict(%{"verdict" => v}) when is_binary(v), do: v
  defp extract_verdict(_), do: nil

  defp format_duration(%Impulse{inserted_at: start, updated_at: finish}) when not is_nil(start) and not is_nil(finish) do
    diff = NaiveDateTime.diff(finish, start, :millisecond)

    cond do
      diff < 1000 -> "#{diff}ms"
      diff < 60_000 -> "#{Float.round(diff / 1000, 1)}s"
      true -> "#{div(diff, 60_000)}m#{rem(div(diff, 1000), 60)}s"
    end
  end

  defp format_duration(_), do: nil

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
