defmodule ExCortex.Tools.ReadPdf do
  @moduledoc "Tool: extract text from a PDF file using pdftotext."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_pdf",
      description: "Extract readable text from a PDF file. Returns up to 10,000 characters.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Absolute path to the PDF file"}
        },
        "required" => ["path"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path}) do
    case System.cmd("pdftotext", [path, "-"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.slice(output, 0, 10_000)}
      {error, _} -> {:error, error}
    end
  end
end
