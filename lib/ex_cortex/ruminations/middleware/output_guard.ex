defmodule ExCortex.Ruminations.Middleware.OutputGuard do
  @moduledoc false
  @behaviour ExCortex.Ruminations.Middleware

  alias ExCortex.Ruminations.Middleware.Context

  require Logger

  @output_patterns [
    {:api_key, ~r/sk-(?:proj-|live-|test-)?[a-zA-Z0-9]{20,}/},
    {:aws_key, ~r/AKIA[0-9A-Z]{16}/},
    {:bearer_token, ~r/Bearer\s+[A-Za-z0-9\-._~+\/]+=*/},
    {:private_key, ~r/-----BEGIN (?:RSA |EC |DSA )?PRIVATE KEY-----/},
    {:password_field, ~r/(?:password|passwd|secret)\s*[:=]\s*["'][^"']+["']/i},
    {:sensitive_path, ~r/(?:\/etc\/shadow|\/etc\/passwd|~\/\.ssh\/id_)/}
  ]

  @tool_arg_patterns [
    {:shell_injection, ~r/;\s*(?:rm|curl|wget|chmod|chown|dd|mkfs|shutdown)/},
    {:command_substitution, ~r/\$\(|`[^`]+`/},
    {:pipe_injection, ~r/\|\s*(?:bash|sh|zsh|exec|eval)/}
  ]

  @impl true
  def before_impulse(%Context{} = ctx, _opts), do: {:cont, ctx}

  @impl true
  def after_impulse(_ctx, result, _opts) when is_binary(result) do
    scan_and_redact(result, @output_patterns)
  end

  def after_impulse(_ctx, result, _opts), do: result

  @impl true
  def wrap_tool_call(tool_name, tool_args, execute_fn) do
    args_text = inspect(tool_args)

    case scan_for_threats(args_text, @tool_arg_patterns) do
      [] ->
        execute_fn.()

      threats ->
        threat_names = Enum.map_join(threats, ", ", &Atom.to_string/1)
        Logger.warning("[OutputGuard] Blocked tool #{tool_name}: #{threat_names}")

        :telemetry.execute([:ex_cortex, :security, :threat], %{event: :output_guard_block, score: 1.0}, %{})

        {:error,
         %{
           error: "Tool call blocked by security scan: #{threat_names}",
           error_type: "SecurityDenied",
           status: "blocked",
           tool: tool_name
         }}
    end
  end

  defp scan_and_redact(text, patterns) do
    Enum.reduce(patterns, text, fn {name, regex}, acc ->
      if Regex.match?(regex, acc) do
        Logger.warning("[OutputGuard] Redacted #{name} from output")

        :telemetry.execute([:ex_cortex, :security, :threat], %{event: :output_guard_redact, score: 1.0}, %{})

        Regex.replace(regex, acc, "[REDACTED:#{name}]")
      else
        acc
      end
    end)
  end

  defp scan_for_threats(text, patterns) do
    Enum.reduce(patterns, [], fn {name, regex}, acc ->
      if Regex.match?(regex, text), do: [name | acc], else: acc
    end)
  end
end
