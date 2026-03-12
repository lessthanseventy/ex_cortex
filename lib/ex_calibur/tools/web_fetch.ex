defmodule ExCalibur.Tools.WebFetch do
  @moduledoc "Tool: fetch a URL and extract readable text using w3m."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "web_fetch",
      description: "Fetch a URL and return readable text content (HTML is converted to plain text via w3m).",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "url" => %{"type" => "string", "description" => "URL to fetch"}
        },
        "required" => ["url"]
      },
      callback: &call/1
    )
  end

  def call(%{"url" => url}) do
    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %{body: body}} when is_binary(body) ->
        case System.cmd("w3m", ["-dump", "-T", "text/html"], input: body, stderr_to_stdout: true) do
          {text, 0} -> {:ok, String.slice(text, 0, 8000)}
          _ -> {:ok, String.slice(body, 0, 8000)}
        end

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end
end
