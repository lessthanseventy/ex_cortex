defmodule ExCortexTUI.Screens.Chat do
  @moduledoc "Shared chat component for Wonder and Muse screens."

  def init(opts) do
    %{
      mode: Keyword.fetch!(opts, :mode),
      title: Keyword.fetch!(opts, :title),
      messages: [],
      input: "",
      streaming: false,
      current_response: ""
    }
  end

  def render(state) do
    header = Owl.Data.tag(state.title, [:bright, :cyan])

    messages_view = Enum.map_intersperse(state.messages, "\n\n", &render_message/1)

    streaming_view =
      if state.streaming do
        cursor =
          if state.current_response == "" do
            Owl.Data.tag("thinking...", :faint)
          else
            [state.current_response, Owl.Data.tag("\u258c", :cyan)]
          end

        [
          "\n\n",
          Owl.Data.tag("cortex: ", [:bright, :cyan]),
          cursor
        ]
      else
        []
      end

    input_view = [
      "\n",
      Owl.Data.tag(String.duplicate("\u2500", 60), :faint),
      "\n",
      if state.streaming do
        Owl.Data.tag("  (streaming... Ctrl+C to cancel)", :faint)
      else
        [Owl.Data.tag("you: ", :faint), state.input, Owl.Data.tag("\u258c", :faint)]
      end
    ]

    List.flatten([header, "\n\n" | messages_view] ++ streaming_view ++ input_view)
  end

  # Enter -- send message (only when not streaming and input is non-empty)
  def handle_key("\r", %{streaming: true} = s), do: {:noreply, s}
  def handle_key("\r", %{input: ""} = s), do: {:noreply, s}

  def handle_key("\r", state) do
    question = state.input
    messages = state.messages ++ [%{role: :user, content: question}]
    new_state = %{state | input: "", messages: messages, streaming: true, current_response: ""}

    app_pid = Process.whereis(ExCortexTUI.App)
    scope = to_string(state.mode)

    Task.start(fn ->
      ExCortex.Muse.stream_ask(
        question,
        fn
          {:token, t} -> send(app_pid, {:chat_token, t})
          :done -> send(app_pid, :chat_done)
          {:error, e} -> send(app_pid, {:chat_error, e})
        end,
        scope: scope
      )
    end)

    {:noreply, new_state}
  end

  # Backspace
  def handle_key(<<127>>, %{streaming: false} = state) do
    {:noreply, %{state | input: String.slice(state.input, 0..-2//1)}}
  end

  # Ctrl+C -- cancel streaming
  def handle_key(<<3>>, %{streaming: true} = state) do
    messages =
      state.messages ++ [%{role: :assistant, content: state.current_response <> " [cancelled]"}]

    {:noreply, %{state | streaming: false, current_response: "", messages: messages}}
  end

  # Regular printable character (not streaming)
  def handle_key(<<c>> = char, %{streaming: false} = state) when c >= 32 and c < 127 do
    {:noreply, %{state | input: state.input <> char}}
  end

  # Ignore everything else
  def handle_key(_, state), do: {:noreply, state}

  # Handle streaming messages
  def handle_info({:chat_token, token}, state) do
    {:noreply, %{state | current_response: state.current_response <> token}}
  end

  def handle_info(:chat_done, state) do
    messages = state.messages ++ [%{role: :assistant, content: state.current_response}]
    {:noreply, %{state | streaming: false, current_response: "", messages: messages}}
  end

  def handle_info({:chat_error, error}, state) do
    messages = state.messages ++ [%{role: :assistant, content: "[Error: #{inspect(error)}]"}]
    {:noreply, %{state | streaming: false, current_response: "", messages: messages}}
  end

  def handle_info(_, state), do: {:noreply, state}

  # Render helpers

  defp render_message(%{role: :user, content: c}) do
    [Owl.Data.tag("you: ", :faint), c]
  end

  defp render_message(%{role: :assistant, content: c}) do
    [Owl.Data.tag("cortex: ", [:bright, :cyan]), c]
  end
end
