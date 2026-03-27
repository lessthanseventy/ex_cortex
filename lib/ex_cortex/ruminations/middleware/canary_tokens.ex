defmodule ExCortex.Ruminations.Middleware.CanaryTokens do
  @moduledoc false
  @behaviour ExCortex.Ruminations.Middleware

  alias ExCortex.Ruminations.Middleware.Context

  require Logger

  @impl true
  def before_impulse(%Context{} = ctx, _opts) do
    token = generate_token()
    canary = "<!-- CANARY:#{token} -->"

    updated_text = "#{canary}\n#{ctx.input_text}"
    updated_meta = Map.put(ctx.metadata, :canary_token, token)

    {:cont, %{ctx | input_text: updated_text, metadata: updated_meta}}
  end

  @impl true
  def after_impulse(%Context{metadata: %{canary_token: token}} = _ctx, result, _opts)
      when is_binary(result) and is_binary(token) do
    if String.contains?(result, token) do
      Logger.warning("[CanaryTokens] Canary token leaked in output — possible prompt extraction")

      :telemetry.execute([:ex_cortex, :security, :threat], %{event: :canary_leak, score: 3.0}, %{})

      String.replace(result, ~r/<!-- CANARY:[a-f0-9]+ -->/, "")
    else
      result
    end
  end

  def after_impulse(_ctx, result, _opts), do: result

  @impl true
  def wrap_tool_call(_tool_name, _tool_args, execute_fn), do: execute_fn.()

  defp generate_token do
    6 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end
end
