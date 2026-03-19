defmodule ExCortexTUI.App do
  @moduledoc "Ratatouille-based terminal UI for ExCortex."

  @behaviour Ratatouille.App

  import Ecto.Query
  import Ratatouille.View

  alias ExCortex.Ruminations.Daydream
  alias ExCortex.Signals.TodoSync
  alias ExCortex.Tools.ObsidianTodos
  alias Ratatouille.Runtime.Command
  alias Ratatouille.Runtime.Subscription

  require Logger

  @nav_items [
    {?a, :daily, "Daily"},
    {?c, :cortex, "Cortex"},
    {?d, :daydreams, "Daydreams"},
    {?p, :proposals, "Proposals"},
    {?w, :wonder, "Wonder"},
    {?m, :muse, "Muse"},
    {?h, :hud, "HUD"},
    {?l, :logs, "Logs"},
    {??, :help, "Help"}
  ]

  @nav_keys Map.new(@nav_items, fn {ch, screen, _} -> {ch, screen} end)
  @chat_screens [:wonder, :muse]

  # ── Ratatouille.App callbacks ──────────────────────────────────────

  @impl true
  def init(%{window: window}) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "signals")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "memory")

    %{
      screen: :daily,
      window: window,
      scroll: 0,
      cursor: 0,
      input: nil,
      input_mode: nil,
      chat_history: [],
      chat_response: "",
      chat_streaming: false,
      daydream_count: safe_daydream_count(),
      proposal_count: safe_proposal_count(),
      daily_signal: load_daily_signal(),
      daydreams: [],
      proposals: [],
      detail: nil
    }
  end

  @impl true
  def subscribe(_model) do
    Subscription.interval(3_000, :tick)
  end

  @impl true
  def update(model, msg) do
    case msg do
      :tick ->
        %{model | daydream_count: safe_daydream_count(), proposal_count: safe_proposal_count()}

      {:daydream_started, _} -> refresh_screen_data(model)
      {:daydream_completed, _} -> refresh_screen_data(model)
      {:signal_posted, _} -> refresh_screen_data(model)
      {:engram_updated, _} -> refresh_screen_data(model)
      {:daily_signal_loaded, signal} -> %{model | daily_signal: signal}
      {:screen_data, data} -> Map.merge(model, data)
      {:todo_synced, _} -> {%{model | daily_signal: load_daily_signal()}, load_daily_cmd()}
      {:chat_token, token} -> %{model | chat_response: model.chat_response <> token}
      {:chat_done, _} -> finish_chat(model)
      {:chat_error, err} -> finish_chat_error(model, err)
      {:event, event} -> handle_key(model, event)
      {:resize, _event} -> model
      _ -> model
    end
  end

  @impl true
  def render(model) do
    top =
      bar do
        label do
          text(content: " ExCortex ", color: :yellow, attributes: [:bold])

          for {ch, screen, name} <- @nav_items do
            if screen == model.screen do
              text(content: " [#{<<ch>>}]#{name} ", color: :cyan, attributes: [:bold])
            else
              text(content: " #{<<ch>>}:#{name} ")
            end
          end
        end
      end

    bottom =
      bar do
        label do
          text(content: " ● ", color: :green)

          if model.daydream_count > 0 do
            text(content: " #{model.daydream_count} running ", color: :yellow, attributes: [:bold])
          else
            text(content: " idle ", color: :white)
          end

          if model.proposal_count > 0 do
            text(content: " #{model.proposal_count} proposals ", color: :magenta, attributes: [:bold])
          end

          if model.input do
            mode_name = input_mode_label(model.input_mode)
            text(content: " [INPUT: #{mode_name}] ", color: :yellow, attributes: [:bold])
          end

          text(content: "  q:quit  esc:back", color: :white)
        end
      end

    view top_bar: top, bottom_bar: bottom do
      render_screen(model)
    end
  rescue
    e ->
      view do
        label(content: "Render error: #{Exception.message(e)}", color: :red)
      end
  end

  # ── Key handling ───────────────────────────────────────────────────

  defp handle_key(model, %{key: key}) when key > 0, do: handle_special_key(model, key)
  defp handle_key(model, %{ch: ch}) when ch > 0, do: handle_char(model, ch)
  defp handle_key(model, _event), do: model

  # Escape
  defp handle_special_key(%{input: input} = model, 27) when not is_nil(input) do
    %{model | input: nil, input_mode: nil}
  end

  defp handle_special_key(%{screen: :daily} = model, 27), do: model
  defp handle_special_key(model, 27), do: switch_screen(model, :daily)

  # Enter
  defp handle_special_key(%{input: input, input_mode: mode} = model, 13) when not is_nil(input) do
    submit_input(model, mode, input)
  end

  defp handle_special_key(%{screen: :daydreams} = model, 13), do: show_daydream_detail(model)
  defp handle_special_key(model, 13), do: model

  # Arrows
  defp handle_special_key(model, 65_517), do: handle_char(model, ?k)
  defp handle_special_key(model, 65_516), do: handle_char(model, ?j)

  # Backspace
  defp handle_special_key(%{input: input} = model, key) when key in [127, 65_522] and not is_nil(input) do
    %{model | input: String.slice(input, 0..-2//1)}
  end

  # Space — toggle todo on daily, or type space in input/chat
  defp handle_special_key(%{screen: :daily, input: nil} = model, 32) do
    toggle_daily_todo(model, model.cursor + 1)
  end

  defp handle_special_key(%{input: input} = model, 32) when not is_nil(input) do
    %{model | input: input <> " "}
  end

  defp handle_special_key(%{screen: screen} = model, 32) when screen in @chat_screens do
    %{model | input: " ", input_mode: :chat}
  end

  defp handle_special_key(model, _key), do: model

  # Input mode — accumulate chars
  defp handle_char(%{input: input} = model, ch) when not is_nil(input) and ch >= 32 do
    %{model | input: input <> <<ch::utf8>>}
  end

  # Chat screens — typing starts input mode
  defp handle_char(%{screen: screen, input: nil} = model, ch)
       when screen in @chat_screens and ch >= 32 and ch not in [?q] do
    %{model | input: <<ch::utf8>>, input_mode: :chat}
  end

  # Nav keys (not in chat)
  defp handle_char(%{screen: screen} = model, ch) when screen not in @chat_screens do
    case Map.get(@nav_keys, ch) do
      nil -> handle_screen_char(model, ch)
      target -> switch_screen(model, target)
    end
  end

  defp handle_char(model, _ch), do: model

  # ── Screen-specific keys ─────────────────────────────────────────

  # Daily
  defp handle_screen_char(%{screen: :daily} = model, ?j), do: cursor_down(model)
  defp handle_screen_char(%{screen: :daily} = model, ?k), do: cursor_up(model)

  defp handle_screen_char(%{screen: :daily} = model, ?r) do
    {%{model | daily_signal: load_daily_signal()}, load_daily_cmd()}
  end

  defp handle_screen_char(%{screen: :daily} = model, ?t), do: %{model | input: "", input_mode: :todo}
  defp handle_screen_char(%{screen: :daily} = model, ?b), do: %{model | input: "", input_mode: :brain_dump}
  defp handle_screen_char(%{screen: :daily} = model, ?e), do: %{model | input: "", input_mode: :what_happened}

  defp handle_screen_char(%{screen: :daily} = model, ch) when ch in ?1..?9 do
    toggle_daily_todo(model, ch - ?0)
  end

  # Cortex
  defp handle_screen_char(%{screen: :cortex} = model, ?j), do: scroll_down(model)
  defp handle_screen_char(%{screen: :cortex} = model, ?k), do: scroll_up(model)

  # Daydreams
  defp handle_screen_char(%{screen: :daydreams} = model, ?j), do: cursor_down(model)
  defp handle_screen_char(%{screen: :daydreams} = model, ?k), do: cursor_up(model)

  # Proposals
  defp handle_screen_char(%{screen: :proposals} = model, ?j), do: cursor_down(model)
  defp handle_screen_char(%{screen: :proposals} = model, ?k), do: cursor_up(model)
  defp handle_screen_char(%{screen: :proposals} = model, ?y), do: approve_current_proposal(model)
  defp handle_screen_char(%{screen: :proposals} = model, ?n), do: reject_current_proposal(model)

  # Logs
  defp handle_screen_char(%{screen: :logs} = model, ?j), do: scroll_down(model)
  defp handle_screen_char(%{screen: :logs} = model, ?k), do: scroll_up(model)

  defp handle_screen_char(model, _ch), do: model

  # ── Screen switching ───────────────────────────────────────────────

  defp switch_screen(model, target) do
    base = %{model | screen: target, scroll: 0, cursor: 0, input: nil, input_mode: nil, detail: nil}

    case target do
      :daily -> %{base | daily_signal: load_daily_signal()}
      :daydreams -> %{base | daydreams: load_daydreams()}
      :proposals -> %{base | proposals: load_proposals()}
      _ -> base
    end
  end

  defp refresh_screen_data(model) do
    model
    |> Map.put(:daydream_count, safe_daydream_count())
    |> Map.put(:proposal_count, safe_proposal_count())
    |> then(fn m ->
      case m.screen do
        :daily -> %{m | daily_signal: load_daily_signal()}
        :daydreams -> %{m | daydreams: load_daydreams()}
        :proposals -> %{m | proposals: load_proposals()}
        _ -> m
      end
    end)
  end

  # ── Screen rendering ──────────────────────────────────────────────

  defp render_screen(%{screen: :daily} = m), do: render_daily(m)
  defp render_screen(%{screen: :cortex} = m), do: render_cortex(m)
  defp render_screen(%{screen: :daydreams} = m), do: render_daydreams(m)
  defp render_screen(%{screen: :proposals} = m), do: render_proposals(m)
  defp render_screen(%{screen: :wonder} = m), do: render_chat(m, "Wonder — pure LLM")
  defp render_screen(%{screen: :muse} = m), do: render_chat(m, "Muse — RAG-grounded")
  defp render_screen(%{screen: :hud} = m), do: render_hud(m)
  defp render_screen(%{screen: :logs} = m), do: render_logs(m)
  defp render_screen(%{screen: :help}), do: render_help()
  defp render_screen(_), do: label(content: "Unknown screen")

  # ── Daily ──────────────────────────────────────────────────────────

  defp render_daily(model) do
    signal = model.daily_signal

    if is_nil(signal) do
      panel title: "Daily", color: :yellow do
        label(content: "  No daily note synced. Press r to refresh.", color: :yellow)
      end
    else
      items = get_in_meta(signal, "items") || []
      brain_dump = get_in_meta(signal, "brain_dump") || []
      what_happened = get_in_meta(signal, "what_happened") || []
      title_text = signal.title || "Today"

      row do
        column size: 12 do
          panel title: title_text, color: :cyan do
            # Todos
            label(content: " what's happening", color: :cyan, attributes: [:bold])
            label(content: "")

            for {item, idx} <- Enum.with_index(items) do
              render_todo_row(item, idx, model.cursor)
            end

            render_daily_input_or_hint(model, :todo, items, "[t] add todo")

            label(content: "")
            label(content: " brain dump", color: :magenta, attributes: [:bold])
            label(content: "")

            for item <- brain_dump do
              label do
                text(content: "   · ", color: :magenta)
                text(content: item_text(item))
              end
            end

            render_daily_input_or_hint(model, :brain_dump, brain_dump, "[b] add to brain dump")

            label(content: "")
            label(content: " what happened", color: :green, attributes: [:bold])
            label(content: "")

            for item <- what_happened do
              render_what_happened_row(item)
            end

            render_daily_input_or_hint(model, :what_happened, what_happened, "[e] log what happened")

            label(content: "")

            label do
              text(content: " j/k", color: :cyan)
              text(content: ":move ")
              text(content: "space", color: :cyan)
              text(content: ":toggle ")
              text(content: "r", color: :cyan)
              text(content: ":refresh")
            end
          end
        end
      end
    end
  end

  # ── Cortex ─────────────────────────────────────────────────────────

  defp render_cortex(model) do
    ruminations = safe_list_ruminations()
    signals = safe_list_signals()
    clusters = safe_list_pathways()
    engrams = safe_list_engrams()

    viewport offset_y: model.scroll do
      row do
        column size: 6 do
          panel title: "Ruminations", color: :cyan do
            for r <- ruminations do
              color = status_color(r.status)

              label do
                text(content: "  ● ", color: color)
                text(content: r.name)
                text(content: "  [#{r.status}]", color: color)
              end
            end
          end

          panel title: "Signals", color: :yellow do
            for s <- signals do
              label do
                text(content: "  #{format_time(s.inserted_at)} ", color: :white)
                text(content: "[#{s.source || s.type || "?"}] ", color: :cyan)
                text(content: truncate(s.title || "", 40))
              end
            end
          end
        end

        column size: 6 do
          panel title: "Clusters", color: :green do
            for c <- clusters do
              label do
                text(content: "  ● ", color: :green)
                text(content: c.cluster_name)
              end
            end
          end

          panel title: "Memory", color: :magenta do
            for e <- engrams do
              importance = String.duplicate("★", min(e.importance || 1, 5))

              label do
                text(content: "  #{importance} ", color: :yellow)
                text(content: truncate(e.title || "untitled", 30))
                text(content: "  [#{e.category}]", color: :white)
              end
            end
          end
        end
      end
    end
  end

  # ── Daydreams ──────────────────────────────────────────────────────

  defp render_daydreams(%{detail: %{} = detail}) do
    panel title: "Daydream Detail", color: :cyan do
      label do
        text(content: "  Rumination: ", color: :cyan, attributes: [:bold])
        text(content: detail.rumination_name)
      end

      label do
        text(content: "  Status:     ", color: :cyan, attributes: [:bold])
        text(content: detail.status, color: status_color(detail.status))
      end

      label do
        text(content: "  Started:    ", color: :cyan, attributes: [:bold])
        text(content: detail.inserted_at)
      end

      if detail.synapse_results do
        label(content: "")
        label(content: "  Synapse Results:", color: :yellow, attributes: [:bold])

        for {name, result} <- detail.synapse_results do
          status = result["status"] || "?"
          color = status_color(status)

          label do
            text(content: "    ● ", color: color)
            text(content: "#{name}: ", attributes: [:bold])
            text(content: truncate(result["output_preview"] || inspect(result), 60))
          end
        end
      end

      label(content: "")
      label(content: "  [esc] back", color: :white)
    end
  end

  defp render_daydreams(model) do
    panel title: "Daydreams", color: :cyan do
      if model.daydreams == [] do
        label(content: "  No recent daydreams.", color: :white)
      else
        for {d, idx} <- Enum.with_index(model.daydreams) do
          name = (d.rumination && d.rumination.name) || "?"
          color = status_color(d.status)
          selected = idx == model.cursor

          label do
            if selected do
              text(content: " ▸ ", color: :cyan, attributes: [:bold])
            else
              text(content: "   ")
            end

            text(content: "● ", color: color)
            text(content: String.pad_trailing(d.status || "?", 12), color: color)
            text(content: name)
            text(content: "  #{format_time(d.inserted_at)}", color: :white)
          end
        end
      end

      label(content: "")

      label do
        text(content: " j/k", color: :cyan)
        text(content: ":navigate ")
        text(content: "enter", color: :cyan)
        text(content: ":detail")
      end
    end
  end

  # ── Proposals ──────────────────────────────────────────────────────

  defp render_proposals(model) do
    panel title: "Proposals", color: :magenta do
      if model.proposals == [] do
        label(content: "  No pending proposals.", color: :white)
      else
        for {p, idx} <- Enum.with_index(model.proposals) do
          selected = idx == model.cursor
          confidence = get_in(p.details || %{}, ["confidence"])
          conf_str = if confidence, do: " (#{Float.round(confidence * 100, 0)}%)", else: ""

          label do
            if selected do
              text(content: " ▸ ", color: :cyan, attributes: [:bold])
            else
              text(content: "   ")
            end

            text(content: "[#{p.type || "?"}]", color: :yellow)
            text(content: " #{truncate(p.description || "?", 50)}")
            text(content: conf_str, color: :cyan)
          end
        end
      end

      label(content: "")

      label do
        text(content: " j/k", color: :cyan)
        text(content: ":navigate ")
        text(content: "y", color: :green)
        text(content: ":approve ")
        text(content: "n", color: :red)
        text(content: ":reject")
      end
    end
  end

  # ── Chat ───────────────────────────────────────────────────────────

  defp render_chat(model, title) do
    panel title: title, color: :green do
      if model.chat_history == [] and !model.chat_streaming and is_nil(model.input) do
        label(content: "  Start typing to chat. Esc to go back.", color: :white)
        label(content: "")
      end

      for {role, content} <- model.chat_history do
        if role == :user do
          label do
            text(content: "  you: ", color: :cyan, attributes: [:bold])
            text(content: truncate(content, 200))
          end
        else
          label do
            text(content: "  cortex: ", color: :green, attributes: [:bold])
            text(content: truncate(content, 200))
          end
        end

        label(content: "")
      end

      if model.chat_streaming do
        label do
          text(content: "  cortex: ", color: :green, attributes: [:bold])
          text(content: model.chat_response)
          text(content: " ▌", color: :green)
        end
      end

      if model.input do
        label(content: "")

        label do
          text(content: "  ❯ ", color: :yellow, attributes: [:bold])
          text(content: model.input)
          text(content: "█", color: :yellow)
        end
      end
    end
  end

  # ── HUD ────────────────────────────────────────────────────────────

  defp render_hud(_model) do
    hud_text =
      try do
        ExCortexTUI.HUD.Formatter.format(ExCortexTUI.HUD.gather_state())
      rescue
        _ -> "HUD unavailable"
      end

    panel title: "HUD — Machine-Readable Dashboard", color: :white do
      for line <- String.split(hud_text, "\n") do
        color =
          cond do
            String.starts_with?(line, "# ") -> :yellow
            String.starts_with?(line, "## ") -> :cyan
            String.contains?(line, "running") -> :yellow
            String.contains?(line, "failed") -> :red
            true -> :white
          end

        label(content: line, color: color)
      end
    end
  end

  # ── Logs ───────────────────────────────────────────────────────────

  defp render_logs(model) do
    lines =
      try do
        ExCortexTUI.LogBuffer.get_lines(50)
      rescue
        _ -> []
      end

    viewport offset_y: model.scroll do
      panel title: "Logs", color: :white do
        if lines == [] do
          label(content: "  No log entries.", color: :white)
        else
          for line <- lines do
            color =
              cond do
                String.contains?(line, "[error]") -> :red
                String.contains?(line, "[warning]") -> :yellow
                String.contains?(line, "[info]") -> :green
                true -> :white
              end

            label(content: "  #{line}", color: color)
          end
        end
      end
    end
  end

  # ── Help ───────────────────────────────────────────────────────────

  defp render_help do
    panel title: "Key Bindings", color: :cyan do
      label(content: "")
      label(content: "  NAVIGATION", color: :yellow, attributes: [:bold])
      label(content: "")

      label do
        text(content: "    a", color: :cyan, attributes: [:bold])
        text(content: " Daily       ")
        text(content: "c", color: :cyan, attributes: [:bold])
        text(content: " Cortex      ")
        text(content: "d", color: :cyan, attributes: [:bold])
        text(content: " Daydreams")
      end

      label do
        text(content: "    p", color: :cyan, attributes: [:bold])
        text(content: " Proposals   ")
        text(content: "w", color: :cyan, attributes: [:bold])
        text(content: " Wonder      ")
        text(content: "m", color: :cyan, attributes: [:bold])
        text(content: " Muse")
      end

      label do
        text(content: "    h", color: :cyan, attributes: [:bold])
        text(content: " HUD         ")
        text(content: "l", color: :cyan, attributes: [:bold])
        text(content: " Logs        ")
        text(content: "?", color: :cyan, attributes: [:bold])
        text(content: " Help")
      end

      label(content: "")
      label(content: "  GENERAL", color: :yellow, attributes: [:bold])
      label(content: "")

      label do
        text(content: "    j/k", color: :cyan, attributes: [:bold])
        text(content: "     Navigate / scroll")
      end

      label do
        text(content: "    Enter", color: :cyan, attributes: [:bold])
        text(content: "   Select / submit input")
      end

      label do
        text(content: "    Esc", color: :cyan, attributes: [:bold])
        text(content: "     Back / cancel input")
      end

      label do
        text(content: "    q", color: :cyan, attributes: [:bold])
        text(content: "       Quit")
      end

      label do
        text(content: "    Ctrl+C", color: :cyan, attributes: [:bold])
        text(content: "  Force quit")
      end

      label(content: "")
      label(content: "  DAILY", color: :yellow, attributes: [:bold])
      label(content: "")

      label do
        text(content: "    space", color: :cyan, attributes: [:bold])
        text(content: "   Toggle selected todo")
      end

      label do
        text(content: "    1-9", color: :cyan, attributes: [:bold])
        text(content: "     Toggle todo by number")
      end

      label do
        text(content: "    t", color: :cyan, attributes: [:bold])
        text(content: "       Add new todo")
      end

      label do
        text(content: "    b", color: :cyan, attributes: [:bold])
        text(content: "       Add to brain dump")
      end

      label do
        text(content: "    e", color: :cyan, attributes: [:bold])
        text(content: "       Log what happened")
      end

      label do
        text(content: "    r", color: :cyan, attributes: [:bold])
        text(content: "       Refresh from Obsidian")
      end

      label(content: "")
      label(content: "  PROPOSALS", color: :yellow, attributes: [:bold])
      label(content: "")

      label do
        text(content: "    y", color: :green, attributes: [:bold])
        text(content: "       Approve")
      end

      label do
        text(content: "    n", color: :red, attributes: [:bold])
        text(content: "       Reject")
      end

      label(content: "")
      label(content: "  CHAT (Wonder/Muse)", color: :yellow, attributes: [:bold])
      label(content: "")
      label(content: "    Type to start input. Enter sends. Esc cancels.")
    end
  end

  # ── Daily row helpers ───────────────────────────────────────────────

  defp render_todo_row(item, idx, cursor) do
    checked = item["checked"] || item["done"] || false
    text_content = item["text"] || item["title"] || "?"
    selected = idx == cursor

    label do
      if selected do
        text(content: " ▸ ", color: :cyan, attributes: [:bold])
      else
        text(content: "   ")
      end

      if checked do
        text(content: "✓ ", color: :green)
        text(content: text_content, attributes: [:dim])
      else
        text(content: "○ ", color: :yellow)
        text(content: text_content, attributes: [:bold])
      end
    end
  end

  defp render_what_happened_row(item) do
    checked = is_map(item) && item["checked"]

    label do
      if checked do
        text(content: "   ✓ ", color: :green)
        text(content: item_text(item), attributes: [:dim])
      else
        text(content: "   · ", color: :green)
        text(content: item_text(item))
      end
    end
  end

  # ── Input box ──────────────────────────────────────────────────────

  defp render_daily_input_or_hint(model, target_mode, _items, _hint_text) when model.input_mode == target_mode do
    input = model.input || ""

    panel color: :yellow do
      label do
        text(content: " #{input_mode_label(target_mode)}: ", color: :yellow, attributes: [:bold])
        text(content: input)
        text(content: "█", color: :yellow)
      end

      label(content: "   Enter to submit, Esc to cancel", color: :white)
    end
  end

  defp render_daily_input_or_hint(_model, _target_mode, _items, hint_text) do
    label(content: "   #{hint_text}", color: :white)
  end

  defp input_mode_label(:todo), do: "New todo"
  defp input_mode_label(:brain_dump), do: "Brain dump"
  defp input_mode_label(:what_happened), do: "What happened"
  defp input_mode_label(:chat), do: "Chat"
  defp input_mode_label(_), do: "Input"

  # ── Input submission ───────────────────────────────────────────────

  defp submit_input(model, :todo, text) do
    {%{model | input: nil, input_mode: nil}, todo_add_cmd(text)}
  end

  defp submit_input(model, :brain_dump, text) do
    {%{model | input: nil, input_mode: nil}, daily_write_cmd(text, "brain dump")}
  end

  defp submit_input(model, :what_happened, text) do
    {%{model | input: nil, input_mode: nil}, daily_write_cmd(text, "what happened")}
  end

  defp submit_input(model, :chat, text) do
    scope = if model.screen == :wonder, do: "wonder", else: "muse"
    history = model.chat_history ++ [{:user, text}]
    runtime_pid = self()

    cmd =
      Command.new(
        fn ->
          callback = fn
            {:token, t} -> send(runtime_pid, {:command_result, {:chat_token, t}})
            :done -> send(runtime_pid, {:command_result, {:chat_done, nil}})
            {:error, e} -> send(runtime_pid, {:command_result, {:chat_error, e}})
          end

          ExCortex.Muse.stream_ask(text, callback, scope: scope)
        end,
        :chat_started
      )

    {%{model | input: nil, input_mode: nil, chat_history: history, chat_response: "", chat_streaming: true}, cmd}
  end

  defp submit_input(model, _mode, _text), do: %{model | input: nil, input_mode: nil}

  defp finish_chat(model) do
    history = model.chat_history ++ [{:assistant, model.chat_response}]
    %{model | chat_history: history, chat_response: "", chat_streaming: false}
  end

  defp finish_chat_error(model, err) do
    history = model.chat_history ++ [{:assistant, "Error: #{inspect(err)}"}]
    %{model | chat_history: history, chat_response: "", chat_streaming: false}
  end

  # ── Actions ────────────────────────────────────────────────────────

  defp toggle_daily_todo(model, index) do
    items = get_in_meta(model.daily_signal, "items") || []

    case Enum.at(items, index - 1) do
      nil ->
        model

      item ->
        text = item["text"] || item["title"]
        checked = item["checked"] || item["done"] || false

        cmd =
          Command.new(
            fn ->
              ObsidianTodos.toggle_todo(%{"text" => text, "done" => !checked})
              TodoSync.sync()
            end,
            {:todo_synced, nil}
          )

        # Optimistic update
        new_items = List.update_at(items, index - 1, &Map.put(&1, "checked", !checked))
        new_signal = put_in(model.daily_signal.metadata, ["items"], new_items)
        {%{model | daily_signal: new_signal}, cmd}
    end
  end

  defp todo_add_cmd(text) do
    Command.new(fn ->
      ObsidianTodos.add_todo(%{"text" => text})
      TodoSync.sync()
    end, {:todo_synced, nil})
  end

  defp daily_write_cmd(text, section) do
    Command.new(fn ->
      ExCortex.Tools.DailyNoteWrite.call(%{"content" => text, "section" => section})
      TodoSync.sync()
    end, {:todo_synced, nil})
  end

  defp approve_current_proposal(model) do
    case Enum.at(model.proposals, model.cursor) do
      nil -> model
      proposal ->
        cmd = Command.new(fn ->
          ExCortex.Ruminations.approve_proposal(proposal)
        end, {:screen_data, %{proposals: load_proposals()}})
        {model, cmd}
    end
  end

  defp reject_current_proposal(model) do
    case Enum.at(model.proposals, model.cursor) do
      nil -> model
      proposal ->
        cmd = Command.new(fn ->
          ExCortex.Ruminations.reject_proposal(proposal)
        end, {:screen_data, %{proposals: load_proposals()}})
        {model, cmd}
    end
  end

  defp show_daydream_detail(model) do
    case Enum.at(model.daydreams, model.cursor) do
      nil -> model
      d ->
        detail = %{
          rumination_name: (d.rumination && d.rumination.name) || "?",
          status: d.status,
          inserted_at: format_time(d.inserted_at),
          input: d.input,
          synapse_results: d.synapse_results
        }
        %{model | detail: detail}
    end
  end

  # ── Scroll / cursor ────────────────────────────────────────────────

  defp scroll_down(model), do: %{model | scroll: model.scroll + 1}
  defp scroll_up(model), do: %{model | scroll: max(0, model.scroll - 1)}
  defp cursor_down(model), do: %{model | cursor: model.cursor + 1}
  defp cursor_up(model), do: %{model | cursor: max(0, model.cursor - 1)}

  # ── Data loading ───────────────────────────────────────────────────

  defp load_daily_signal do
    Enum.find(ExCortex.Signals.list_signals(), &(&1.pin_slug == "daily-todos"))
  rescue
    _ -> nil
  end

  defp load_daily_cmd do
    Command.new(fn -> load_daily_signal() end, {:daily_signal_loaded, nil})
  end

  defp load_daydreams do
    ExCortex.Repo.all(from d in Daydream, order_by: [desc: d.inserted_at], limit: 20, preload: [:rumination])
  rescue
    _ -> []
  end

  defp load_proposals do
    ExCortex.Ruminations.list_proposals(status: "pending")
  rescue
    _ -> []
  end

  defp safe_daydream_count do
    ExCortex.Repo.aggregate(from(d in Daydream, where: d.status == "running"), :count)
  rescue
    _ -> 0
  end

  defp safe_proposal_count do
    length(ExCortex.Ruminations.list_proposals(status: "pending"))
  rescue
    _ -> 0
  end

  defp safe_list_ruminations do
    Enum.take(ExCortex.Ruminations.list_ruminations(), 5)
  rescue
    _ -> []
  end

  defp safe_list_signals do
    ExCortex.Signals.list_signals(limit: 5)
  rescue
    _ -> []
  end

  defp safe_list_pathways do
    Enum.take(ExCortex.Clusters.list_pathways(), 5)
  rescue
    _ -> []
  end

  defp safe_list_engrams do
    ExCortex.Memory.list_engrams(limit: 5)
  rescue
    _ -> []
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp get_in_meta(nil, _key), do: nil
  defp get_in_meta(signal, key), do: Map.get(signal.metadata || %{}, key)

  defp status_color("running"), do: :yellow
  defp status_color("complete"), do: :green
  defp status_color("completed"), do: :green
  defp status_color("failed"), do: :red
  defp status_color("interrupted"), do: :magenta
  defp status_color(_), do: :white

  defp format_time(nil), do: "?"
  defp format_time(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_time(_), do: "?"

  defp truncate(nil, _len), do: ""
  defp truncate(s, len) when is_binary(s) and byte_size(s) <= len, do: s
  defp truncate(s, len) when is_binary(s), do: String.slice(s, 0, len) <> "…"
  defp truncate(s, len), do: truncate(inspect(s), len)

  defp item_text(%{"text" => text}), do: text
  defp item_text(%{"title" => title}), do: title
  defp item_text(item) when is_binary(item), do: item
  defp item_text(item), do: inspect(item)
end
