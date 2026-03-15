defmodule ExCortexTUI.Screens.Guide do
  @moduledoc "Guide screen: static help text explaining screens and keyboard shortcuts."

  alias ExCortexTUI.Components.KeyHints
  alias ExCortexTUI.Components.Panel
  alias ExCortexTUI.Components.Status

  def render(_state) do
    hints =
      KeyHints.render([
        {"c", "Cortex"},
        {"n", "Neurons"},
        {"t", "Thoughts"},
        {"m", "Memory"},
        {"s", "Senses"},
        {"i", "Instinct"},
        {"q", "Quit"}
      ])

    Enum.join(
      [
        Panel.render("ExCortex TUI — Guide", screens_text()),
        Panel.render("Keyboard Shortcuts", shortcuts_text()),
        Panel.render("Data Model", data_model_text()),
        "",
        hints
      ],
      "\n"
    )
  end

  defp screens_text do
    Enum.join(
      [
        Status.render(:cyan, "Cortex [c]") <> "  — Dashboard overview.",
        "  Active thoughts, recent signals, cluster health, and",
        "  the five most recently stored engrams.",
        "",
        Status.render(:cyan, "Neurons [n]") <> "  — Cluster & neuron browser.",
        "  Lists every installed cluster and the neurons (role",
        "  agents) that belong to it.",
        "",
        Status.render(:cyan, "Thoughts [t]") <> "  — Thought pipeline list.",
        "  Shows name, status, trigger type, and synapse count",
        "  for every thought in the system.",
        "",
        Status.render(:cyan, "Memory [m]") <> "  — Engram browser.",
        "  Recent memory engrams with title, category, and a",
        "  five-point importance bar.",
        "",
        Status.render(:cyan, "Senses [s]") <> "  — Sense & reflex list.",
        "  Active sense workers (git, feed, webhook, url…) and",
        "  their configured reflexes and streams.",
        "",
        Status.render(:cyan, "Instinct [i]") <> "  — App settings.",
        "  Ollama URL, API key presence, banner text, and",
        "  configured expression (expression) outputs.",
        "",
        Status.render(:cyan, "Guide [g]") <> "  — This screen."
      ],
      "\n"
    )
  end

  defp shortcuts_text do
    Enum.join(
      [
        "  c  →  Cortex dashboard",
        "  n  →  Neurons screen",
        "  t  →  Thoughts screen",
        "  m  →  Memory screen",
        "  s  →  Senses screen",
        "  i  →  Instinct / settings",
        "  g  →  Guide (this screen)",
        "  q  →  Quit the TUI"
      ],
      "\n"
    )
  end

  defp data_model_text do
    Enum.join(
      [
        "Clusters     — pre-built agent teams (formerly Clusters)",
        "Neurons      — role agents within a cluster (formerly Neurons)",
        "Thoughts     — structured pipelines (formerly Thoughts)",
        "Synapses     — pipeline steps (formerly Thought Steps)",
        "Engrams      — stored memory / engrams",
        "Senses       — data-source workers (git, feed, webhook…)",
        "Signals      — events emitted by senses",
        "Expressions  — output channels (email, Slack, webhook…)",
        "Instinct     — app settings and configuration"
      ],
      "\n"
    )
  end
end
