defmodule ExCalibur.Board do
  @moduledoc """
  Pre-configured quest templates for the Quest Board.

  Templates are organized by category and declare hard requirements
  (source types and herald types that must be configured) so the UI
  can show which quests are ready to install today.
  """

  import Ecto.Query

  alias ExCalibur.Heralds.Herald
  alias ExCalibur.Repo
  alias ExCalibur.Sources.Source
  alias Excellence.Schemas.Member

  defstruct [
    :id,
    :name,
    :category,
    :description,
    :suggested_team,
    :requires,
    :step_definitions,
    :quest_definition,
    source_definitions: []
  ]

  @categories [:triage, :reporting, :generation, :review, :onboarding, :lifestyle]

  def categories, do: @categories

  def all do
    triage() ++ reporting() ++ generation() ++ review() ++ onboarding() ++ lifestyle()
  end

  def by_category(cat), do: Enum.filter(all(), &(&1.category == cat))

  def get(id), do: Enum.find(all(), &(&1.id == id))

  @doc """
  Check which requirements are met for a template.
  Returns list of {met :: boolean, label :: String.t} tuples.
  """
  def check_requirements(%__MODULE__{requires: requires}) do
    Enum.map(requires, fn
      {:source_type, type} ->
        met =
          Repo.exists?(
            from(s in Source,
              where: s.source_type == ^type and s.status in ["active", "paused"]
            )
          )

        {met, "#{humanize(type)} source"}

      {:herald_type, type} ->
        met = Repo.exists?(from(h in Herald, where: h.type == ^type))
        {met, "#{humanize(type)} herald"}

      :any_members ->
        met =
          Repo.exists?(from(m in Member, where: m.type == "role" and m.status == "active"))

        {met, "Active members"}
    end)
  end

  @doc """
  Returns :ready | :almost | :unavailable based on requirements.
  :ready — all met
  :almost — only one missing
  :unavailable — two or more missing
  """
  def readiness(%__MODULE__{requires: []} = _template), do: :ready

  def readiness(template) do
    results = check_requirements(template)
    missing = Enum.count(results, fn {met, _} -> !met end)

    cond do
      missing == 0 -> :ready
      missing == 1 -> :almost
      true -> :unavailable
    end
  end

  @doc """
  Install a template: creates its steps and quest.
  Returns {:ok, quest} or {:error, reason}.
  """
  def install(%__MODULE__{} = template) do
    Enum.each(template.step_definitions || [], fn attrs ->
      ExCalibur.Quests.create_step(attrs)
    end)

    step_by_name = Map.new(ExCalibur.Quests.list_steps(), &{&1.name, &1.id})

    steps =
      (template.quest_definition || %{steps: []}).steps
      |> Kernel.||([])
      |> Enum.map(fn step ->
        %{"step_id" => Map.get(step_by_name, step["step_name"]), "flow" => step["flow"]}
      end)
      |> Enum.reject(fn step -> is_nil(step["step_id"]) end)

    result =
      if template.quest_definition do
        ExCalibur.Quests.create_quest(Map.put(template.quest_definition, :steps, steps))
      else
        {:ok, nil}
      end

    Enum.each(template.source_definitions || [], fn source_def ->
      existing =
        Repo.exists?(
          from(s in Source,
            where: s.name == ^source_def.name and s.source_type == ^source_def.source_type
          )
        )

      if !existing do
        Repo.insert(%Source{
          name: source_def.name,
          source_type: source_def.source_type,
          config: source_def.config,
          status: "active",
          book_id: source_def[:book_id]
        })
      end
    end)

    result
  end

  defp humanize(str), do: str |> String.replace("_", " ") |> String.capitalize()

  # ---------------------------------------------------------------------------
  # Template definitions — loaded by all/0
  # ---------------------------------------------------------------------------

  defp triage, do: ExCalibur.Board.Triage.templates()
  defp reporting, do: ExCalibur.Board.Reporting.templates()
  defp generation, do: ExCalibur.Board.Generation.templates()
  defp review, do: ExCalibur.Board.Review.templates()
  defp onboarding, do: ExCalibur.Board.Onboarding.templates()
  defp lifestyle, do: ExCalibur.Board.Lifestyle.templates()
end
