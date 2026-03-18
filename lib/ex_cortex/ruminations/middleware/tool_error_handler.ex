defmodule ExCortex.Ruminations.Middleware.ToolErrorHandler do
  @moduledoc false
  @behaviour ExCortex.Ruminations.Middleware

  alias ExCortex.Ruminations.Middleware.Context

  @impl true
  def before_impulse(%Context{} = ctx, _opts), do: {:cont, ctx}

  @impl true
  def after_impulse(%Context{}, result, _opts), do: result

  @impl true
  def wrap_tool_call(tool_name, _tool_args, execute_fn) do
    execute_fn.()
  catch
    kind, reason ->
      {error_msg, error_type} = format_error(kind, reason)

      {:error,
       %{
         error: error_msg,
         error_type: error_type,
         status: "error",
         tool: tool_name
       }}
  end

  defp format_error(:error, %{__struct__: struct} = exception) do
    {Exception.message(exception), struct |> Module.split() |> Enum.join(".")}
  end

  defp format_error(:throw, value) do
    {inspect(value), "throw"}
  end

  defp format_error(:exit, reason) do
    {inspect(reason), "exit"}
  end
end
