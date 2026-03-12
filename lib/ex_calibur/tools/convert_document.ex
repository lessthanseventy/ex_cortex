defmodule ExCalibur.Tools.ConvertDocument do
  @moduledoc "Tool: convert documents between formats using pandoc."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "convert_document",
      description: "Convert a document between formats using pandoc (e.g. docx to markdown, html to plain text).",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Absolute path to the input file"},
          "from" => %{"type" => "string", "description" => "Input format (e.g. 'docx', 'html', 'rst')"},
          "to" => %{"type" => "string", "description" => "Output format (e.g. 'markdown', 'plain', 'html')"}
        },
        "required" => ["path", "from", "to"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path, "from" => from, "to" => to}) do
    case System.cmd("pandoc", [path, "-f", from, "-t", to], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end
end
