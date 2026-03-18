defmodule ExCortex.Ruminations.Middleware.MessageQueueInjectorTest do
  use ExUnit.Case, async: true

  alias ExCortex.Ruminations.Middleware.Context
  alias ExCortex.Ruminations.Middleware.MessageQueueInjector

  describe "before_impulse/2" do
    test "passes through when no daydream" do
      ctx = %Context{input_text: "hello", metadata: %{}}
      assert {:cont, ^ctx} = MessageQueueInjector.before_impulse(ctx, [])
    end

    test "passes through when daydream has nil id" do
      ctx = %Context{input_text: "hello", daydream: %{id: nil}, metadata: %{}}
      assert {:cont, ^ctx} = MessageQueueInjector.before_impulse(ctx, [])
    end

    test "passes through when no messages in inbox" do
      id = System.unique_integer([:positive])
      ctx = %Context{input_text: "hello", daydream: %{id: id}, metadata: %{}}
      assert {:cont, ^ctx} = MessageQueueInjector.before_impulse(ctx, [])
    end

    test "drains inbox messages and prepends them to input_text" do
      id = System.unique_integer([:positive])
      topic = "daydream:#{id}:inbox"

      # Pre-subscribe so broadcast delivers to our process mailbox
      Phoenix.PubSub.subscribe(ExCortex.PubSub, topic)

      Phoenix.PubSub.broadcast(
        ExCortex.PubSub,
        topic,
        {:inbox_message,
         %{
           from: "slack",
           content: "please also check the tests"
         }}
      )

      Phoenix.PubSub.broadcast(
        ExCortex.PubSub,
        topic,
        {:inbox_message,
         %{
           from: "email",
           content: "deadline moved to Friday"
         }}
      )

      # Allow messages to arrive
      Process.sleep(10)

      ctx = %Context{input_text: "original task", daydream: %{id: id}, metadata: %{}}
      assert {:cont, updated} = MessageQueueInjector.before_impulse(ctx, [])

      assert updated.input_text =~ "## Inbound Messages"
      assert updated.input_text =~ "**slack:** please also check the tests"
      assert updated.input_text =~ "**email:** deadline moved to Friday"
      assert updated.input_text =~ "original task"
      # Messages section comes before original input
      assert String.starts_with?(updated.input_text, "## Inbound Messages")
    end

    test "subscribes to the daydream inbox topic" do
      id = System.unique_integer([:positive])
      topic = "daydream:#{id}:inbox"

      ctx = %Context{input_text: "hello", daydream: %{id: id}, metadata: %{}}
      assert {:cont, _} = MessageQueueInjector.before_impulse(ctx, [])

      # After before_impulse, we should be subscribed — broadcast should arrive
      Phoenix.PubSub.broadcast(
        ExCortex.PubSub,
        topic,
        {:inbox_message,
         %{
           from: "test",
           content: "post-subscribe message"
         }}
      )

      assert_receive {:inbox_message, %{from: "test", content: "post-subscribe message"}}
    end
  end

  describe "after_impulse/3" do
    test "passes through result" do
      ctx = %Context{input_text: "test", metadata: %{}}
      assert :some_result == MessageQueueInjector.after_impulse(ctx, :some_result, [])
    end
  end

  describe "wrap_tool_call/3" do
    test "passes through" do
      assert :tool_result == MessageQueueInjector.wrap_tool_call("tool", %{}, fn -> :tool_result end)
    end
  end
end
