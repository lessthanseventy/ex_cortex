defmodule ExCortex.Ruminations.Middleware.MessageQueueInjector do
  @moduledoc false
  @behaviour ExCortex.Ruminations.Middleware

  alias ExCortex.Ruminations.Middleware.Context

  @impl true
  def before_impulse(%Context{daydream: %{id: daydream_id}} = ctx, _opts) when not is_nil(daydream_id) do
    topic = "daydream:#{daydream_id}:inbox"
    Phoenix.PubSub.subscribe(ExCortex.PubSub, topic)

    messages = drain_inbox([])

    if messages == [] do
      {:cont, ctx}
    else
      section = format_messages(messages)
      {:cont, %{ctx | input_text: "#{section}\n\n#{ctx.input_text}"}}
    end
  end

  def before_impulse(%Context{} = ctx, _opts), do: {:cont, ctx}

  @impl true
  def after_impulse(%Context{}, result, _opts), do: result

  @impl true
  def wrap_tool_call(_tool_name, _tool_args, execute_fn), do: execute_fn.()

  defp drain_inbox(acc) do
    receive do
      {:inbox_message, msg} -> drain_inbox(acc ++ [msg])
    after
      0 -> acc
    end
  end

  defp format_messages(messages) do
    lines =
      Enum.map_join(messages, "\n", fn msg ->
        "- **#{msg.from}:** #{msg.content}"
      end)

    "## Inbound Messages\n#{lines}"
  end
end
