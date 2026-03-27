defmodule ExCortex.Ruminations.Middleware.SystemAuthNonceTest do
  use ExUnit.Case, async: true

  alias ExCortex.Ruminations.Middleware.Context
  alias ExCortex.Ruminations.Middleware.SystemAuthNonce

  describe "before_impulse/2" do
    test "prefixes system content with nonce" do
      ctx = %Context{
        input_text: "Analyze this",
        metadata: %{},
        daydream: %{id: 1}
      }

      {:cont, updated} = SystemAuthNonce.before_impulse(ctx, [])

      assert updated.input_text =~ ~r/\[SYS:[a-f0-9]{8}\]/
      assert updated.metadata[:auth_nonce]
    end

    test "includes instruction about nonce verification" do
      ctx = %Context{
        input_text: "Analyze this",
        metadata: %{},
        daydream: %{id: 1}
      }

      {:cont, updated} = SystemAuthNonce.before_impulse(ctx, [])
      assert updated.input_text =~ "Messages from the system are prefixed"
    end

    test "reuses nonce for same daydream" do
      ctx = %Context{
        input_text: "First",
        metadata: %{auth_nonce: "existing1"},
        daydream: %{id: 1}
      }

      {:cont, updated} = SystemAuthNonce.before_impulse(ctx, [])
      assert updated.metadata[:auth_nonce] == "existing1"
    end
  end

  describe "after_impulse/3" do
    test "passes through" do
      ctx = %Context{input_text: "", metadata: %{}}
      assert SystemAuthNonce.after_impulse(ctx, "result", []) == "result"
    end
  end

  describe "wrap_tool_call/3" do
    test "passes through" do
      assert SystemAuthNonce.wrap_tool_call("t", %{}, fn -> :ok end) == :ok
    end
  end
end
