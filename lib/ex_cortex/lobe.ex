defmodule ExCortex.Lobe do
  @moduledoc """
  Behavioral lobes — functional brain regions that influence how clusters process information.

  Each lobe carries four layers:
  - **Prompt** (A): system prompt text injected into every synapse in this lobe
  - **Pipeline** (B): structural preferences for rumination shape
  - **Processing** (C): runtime tuning knobs (tool iterations, memory depth, preferred tools)
  - **Laterality** (D): left/right hemisphere bias affecting consensus strategy
  """

  defstruct [:id, :name, :label, :description, :prompt, :pipeline, :processing, :laterality]

  @type id :: :frontal | :temporal | :parietal | :occipital | :limbic | :cerebellar

  def all, do: [frontal(), temporal(), parietal(), occipital(), limbic(), cerebellar()]

  def get(id) when is_atom(id), do: Enum.find(all(), &(&1.id == id))
  def get(_), do: nil

  def ids, do: [:frontal, :temporal, :parietal, :occipital, :limbic, :cerebellar]

  def label(id) do
    case get(id) do
      nil -> "Unknown"
      lobe -> lobe.label
    end
  end

  # ---------------------------------------------------------------------------
  # Frontal — Executive function, planning, decision-making
  # ---------------------------------------------------------------------------

  def frontal do
    %__MODULE__{
      id: :frontal,
      name: "Frontal",
      label: "Executive — Planning & Decision",
      description:
        "Planning, risk assessment, decision-making, code review, security analysis. " <>
          "The frontal lobe breaks problems into steps, considers consequences, and gates output through review.",
      prompt:
        "Break complex problems into steps. Consider second-order consequences. " <>
          "Identify risks before acting. Structure your reasoning explicitly. " <>
          "When uncertain, enumerate options with trade-offs rather than guessing.",
      pipeline: %{
        prepend_steps: [:plan],
        append_steps: [:review],
        pattern: :plan_execute_review,
        min_steps: 3
      },
      processing: %{
        max_tool_iterations: 20,
        memory_depth: :standard,
        preferred_tools: ["read_file", "run_sandbox", "search_github"],
        output_style: :detailed
      },
      laterality: %{
        hemisphere: :left,
        consensus_bias: :systematic,
        confidence_threshold: 0.75
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Temporal — Memory, pattern recognition, classification
  # ---------------------------------------------------------------------------

  def temporal do
    %__MODULE__{
      id: :temporal,
      name: "Temporal",
      label: "Memory & Pattern — Classification & Language",
      description:
        "Memory retrieval, pattern recognition, classification, email processing, language analysis. " <>
          "The temporal lobe grounds reasoning in existing knowledge and identifies recurring patterns.",
      prompt:
        "Query the engram store before reasoning. Ground your analysis in existing knowledge. " <>
          "Identify patterns across history. Classify before acting. " <>
          "When you recognize a pattern, name it and cite the prior instances.",
      pipeline: %{
        prepend_steps: [:memory_query],
        append_steps: [],
        pattern: :recall_classify_act,
        min_steps: 2
      },
      processing: %{
        max_tool_iterations: 15,
        memory_depth: :deep,
        preferred_tools: ["query_memory", "search_email", "read_email"],
        output_style: :concise
      },
      laterality: %{
        hemisphere: :left,
        consensus_bias: :systematic,
        confidence_threshold: 0.7
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Parietal — Integration, synthesis, cross-source reasoning
  # ---------------------------------------------------------------------------

  def parietal do
    %__MODULE__{
      id: :parietal,
      name: "Parietal",
      label: "Integration — Synthesis & Research",
      description:
        "Cross-source synthesis, research digests, connecting disparate signals, market analysis. " <>
          "The parietal lobe finds threads linking seemingly unrelated information across multiple sources.",
      prompt:
        "Synthesize across multiple sources. Connect disparate signals. " <>
          "Find the thread that links seemingly unrelated information. " <>
          "Always include source URLs. Cite where each insight originated.",
      pipeline: %{
        prepend_steps: [],
        append_steps: [:synthesize],
        pattern: :gather_analyze_publish,
        min_steps: 3
      },
      processing: %{
        max_tool_iterations: 15,
        memory_depth: :standard,
        preferred_tools: ["fetch_url", "web_search", "query_memory"],
        output_style: :narrative
      },
      laterality: %{
        hemisphere: :right,
        consensus_bias: :divergent,
        confidence_threshold: 0.6
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Occipital — Perception, media processing, visual analysis
  # ---------------------------------------------------------------------------

  def occipital do
    %__MODULE__{
      id: :occipital,
      name: "Occipital",
      label: "Perception — Media & Visual Processing",
      description:
        "Image analysis, video transcription, document OCR, visual pattern recognition. " <>
          "The occipital lobe processes raw sensory input before reasoning about content.",
      prompt:
        "Describe what you see in detail. Extract text, structure, and visual patterns. " <>
          "Process media before reasoning about content. " <>
          "When analyzing documents, extract structure (headings, tables, lists) before summarizing.",
      pipeline: %{
        prepend_steps: [:media_analysis],
        append_steps: [],
        pattern: :perceive_interpret_report,
        min_steps: 2
      },
      processing: %{
        max_tool_iterations: 10,
        memory_depth: :shallow,
        preferred_tools: ["describe_image", "read_image_text", "transcribe_audio", "analyze_video", "read_pdf"],
        output_style: :detailed
      },
      laterality: %{
        hemisphere: :right,
        consensus_bias: :divergent,
        confidence_threshold: 0.55
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Limbic — Emotion, social awareness, cultural processing
  # ---------------------------------------------------------------------------

  def limbic do
    %__MODULE__{
      id: :limbic,
      name: "Limbic",
      label: "Emotional — Social & Cultural",
      description:
        "Sentiment analysis, tone detection, cultural commentary, personal wellness, social signals. " <>
          "The limbic system reads emotional registers and considers human impact.",
      prompt:
        "Read the emotional register. Detect tone, urgency, and frustration. " <>
          "Consider human impact. Be empathetic in framing. Prioritize wellbeing. " <>
          "When content has emotional weight, acknowledge it before analyzing.",
      pipeline: %{
        prepend_steps: [:sentiment],
        append_steps: [:tone_check],
        pattern: :sense_feel_respond,
        min_steps: 2
      },
      processing: %{
        max_tool_iterations: 10,
        memory_depth: :standard,
        preferred_tools: ["query_memory", "web_search"],
        output_style: :narrative
      },
      laterality: %{
        hemisphere: :right,
        consensus_bias: :divergent,
        confidence_threshold: 0.5
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Cerebellar — Coordination, monitoring, ops, procedural precision
  # ---------------------------------------------------------------------------

  def cerebellar do
    %__MODULE__{
      id: :cerebellar,
      name: "Cerebellar",
      label: "Coordination — Ops & Monitoring",
      description:
        "System health monitoring, dependency audits, scheduling, anomaly detection, incident response. " <>
          "The cerebellum coordinates precise, repeatable operations and detects deviations from normal.",
      prompt:
        "Check metrics and status. Detect anomalies. Report precisely with timestamps and severity. " <>
          "No speculation — facts only. When something deviates from baseline, quantify the deviation.",
      pipeline: %{
        prepend_steps: [],
        append_steps: [:alert],
        pattern: :watch_detect_alert,
        min_steps: 2
      },
      processing: %{
        max_tool_iterations: 8,
        memory_depth: :shallow,
        preferred_tools: ["run_sandbox", "query_jaeger", "read_file", "list_files"],
        output_style: :concise
      },
      laterality: %{
        hemisphere: :left,
        consensus_bias: :systematic,
        confidence_threshold: 0.8
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Lookup helpers
  # ---------------------------------------------------------------------------

  @doc """
  Returns a synapse definition map for a pipeline step type.
  Used by install flows to stamp out lobe-shaped rumination structures.
  """
  def pipeline_step_def(:plan, cluster, analyst) do
    %{
      name_suffix: "Plan",
      description:
        "Break the task into explicit steps. Identify what information is needed, what order to process it, and what risks to watch for.",
      output_type: "freeform",
      cluster_name: cluster,
      roster: [%{"who" => "all", "preferred_who" => analyst, "how" => "solo", "when" => "sequential"}]
    }
  end

  def pipeline_step_def(:memory_query, cluster, analyst) do
    %{
      name_suffix: "Recall",
      description:
        "Query the engram store for relevant prior knowledge. Search by tags and keywords. Summarize what existing memory says about this topic.",
      output_type: "freeform",
      cluster_name: cluster,
      loop_tools: ["query_memory"],
      roster: [%{"who" => "all", "preferred_who" => analyst, "how" => "solo", "when" => "sequential"}]
    }
  end

  def pipeline_step_def(:sentiment, cluster, analyst) do
    %{
      name_suffix: "Sentiment",
      description:
        "Assess the emotional tone and social context of the input. Note urgency, frustration, excitement, or neutrality. Flag anything that needs careful handling.",
      output_type: "freeform",
      cluster_name: cluster,
      roster: [%{"who" => "all", "preferred_who" => analyst, "how" => "solo", "when" => "sequential"}]
    }
  end

  def pipeline_step_def(:media_analysis, cluster, analyst) do
    %{
      name_suffix: "Perceive",
      description:
        "Process the raw media input. Extract text, structure, and visual patterns. Describe what you see before interpreting.",
      output_type: "freeform",
      cluster_name: cluster,
      loop_tools: ["describe_image", "read_image_text", "transcribe_audio", "read_pdf"],
      roster: [%{"who" => "all", "preferred_who" => analyst, "how" => "solo", "when" => "sequential"}]
    }
  end

  def pipeline_step_def(:review, cluster, analyst) do
    %{
      name_suffix: "Review",
      description:
        "Review the output so far for errors, omissions, and quality. Flag anything that needs correction before publishing.",
      output_type: "freeform",
      cluster_name: cluster,
      roster: [%{"who" => "all", "preferred_who" => analyst, "how" => "solo", "when" => "sequential"}]
    }
  end

  def pipeline_step_def(:tone_check, cluster, analyst) do
    %{
      name_suffix: "Tone Check",
      description:
        "Review the output for appropriate tone. Ensure empathetic framing, no dismissiveness, and constructive language.",
      output_type: "freeform",
      cluster_name: cluster,
      roster: [%{"who" => "all", "preferred_who" => analyst, "how" => "solo", "when" => "sequential"}]
    }
  end

  def pipeline_step_def(:synthesize, cluster, analyst) do
    %{
      name_suffix: "Synthesize",
      description:
        "Pull together insights from all sources into a coherent narrative. Identify the connecting threads and highlight what matters most.",
      output_type: "freeform",
      cluster_name: cluster,
      roster: [%{"who" => "all", "preferred_who" => analyst, "how" => "solo", "when" => "sequential"}]
    }
  end

  def pipeline_step_def(:alert, cluster, analyst) do
    %{
      name_suffix: "Alert",
      description:
        "Format findings as a concise alert with severity, timestamp, and recommended action. Facts only — no speculation.",
      output_type: "signal",
      cluster_name: cluster,
      roster: [%{"who" => "all", "preferred_who" => analyst, "how" => "solo", "when" => "sequential"}]
    }
  end

  def pipeline_step_def(_, cluster, analyst) do
    %{
      name_suffix: "Process",
      description: "Process the input according to the pipeline's requirements.",
      output_type: "freeform",
      cluster_name: cluster,
      roster: [%{"who" => "all", "preferred_who" => analyst, "how" => "solo", "when" => "sequential"}]
    }
  end

  @doc """
  Resolve the lobe prompt for a cluster name by looking up its pathway metadata.
  Returns the prompt string or nil if no pathway/lobe is found.
  """
  def prompt_for_cluster(nil), do: nil

  def prompt_for_cluster(cluster_name) do
    case ExCortex.Evaluator.pathways()[cluster_name] do
      nil -> nil
      mod -> mod.metadata() |> Map.get(:lobe) |> prompt_for_lobe()
    end
  end

  @doc "Get the prompt string for a lobe id atom."
  def prompt_for_lobe(nil), do: nil
  def prompt_for_lobe(lobe_id) when is_atom(lobe_id), do: get(lobe_id) && get(lobe_id).prompt

  @doc """
  Resolve the laterality config for a cluster name.
  Returns the laterality map or nil if no pathway/lobe is found.
  """
  def laterality_for_cluster(nil), do: nil

  def laterality_for_cluster(cluster_name) do
    case ExCortex.Evaluator.pathways()[cluster_name] do
      nil -> nil
      mod -> mod.metadata() |> Map.get(:lobe) |> laterality_for_lobe()
    end
  end

  defp laterality_for_lobe(nil), do: nil
  defp laterality_for_lobe(lobe_id), do: get(lobe_id) && get(lobe_id).laterality
end
