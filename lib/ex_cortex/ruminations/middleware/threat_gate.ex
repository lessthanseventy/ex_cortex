defmodule ExCortex.Ruminations.Middleware.ThreatGate do
  @moduledoc false
  @behaviour ExCortex.Ruminations.Middleware

  alias ExCortex.Ruminations.Middleware.Context
  alias ExCortex.Security.ThreatTracker

  require Logger

  @impl true
  def before_impulse(%Context{daydream: nil} = ctx, _opts), do: {:cont, ctx}

  def before_impulse(%Context{daydream: %{id: daydream_id}} = ctx, _opts) do
    case ThreatTracker.check(daydream_id) do
      :halt ->
        Logger.error("[ThreatGate] Halting daydream #{daydream_id} — threat score exceeded halt threshold")

        {:halt, :threat_threshold_exceeded}

      :warn ->
        Logger.warning("[ThreatGate] Elevated threat score for daydream #{daydream_id}")
        {:cont, ctx}

      :ok ->
        {:cont, ctx}
    end
  end

  def before_impulse(%Context{} = ctx, _opts), do: {:cont, ctx}

  @impl true
  def after_impulse(_ctx, result, _opts), do: result

  @impl true
  def wrap_tool_call(_tool_name, _tool_args, execute_fn), do: execute_fn.()
end
