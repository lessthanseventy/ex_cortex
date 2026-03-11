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
    :banner,
    :description,
    :suggested_team,
    :requires,
    :step_definitions,
    :quest_definition,
    source_definitions: [],
    extra_quests: []
  ]

  @categories [:triage, :reporting, :generation, :review, :onboarding, :lifestyle]

  def categories, do: @categories

  def all do
    triage() ++ reporting() ++ generation() ++ review() ++ onboarding() ++ lifestyle()
  end

  def by_category(cat), do: Enum.filter(all(), &(&1.category == cat))

  def get(id), do: Enum.find(all(), &(&1.id == id))

  def filter_by_banner(banner) do
    Enum.filter(all(), &(&1.banner == banner))
  end

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

      {:not_installed, template_id} ->
        quest_prefix = template_id_to_quest_prefix(template_id)

        installed =
          Repo.exists?(
            from(q in ExCalibur.Quests.Quest,
              where: q.status in ["active", "paused"],
              where: like(q.name, ^"%#{quest_prefix}%")
            )
          )

        {!installed, "Not included in #{humanize(template_id)}"}
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
    require Logger

    Enum.each(template.step_definitions || [], fn attrs ->
      case ExCalibur.Quests.create_step(attrs) do
        {:ok, step} ->
          Logger.debug("[Board] Created step #{step.id} (#{step.name})")

        {:error, changeset} ->
          errors = ExCalibur.Board.changeset_errors(changeset)

          if Enum.any?(changeset.errors, fn {field, {_, opts}} ->
               field == :name && opts[:constraint] == :unique
             end) do
            Logger.debug("[Board] Step already exists: #{attrs[:name] || attrs["name"]}")
          else
            Logger.warning("[Board] Failed to create step #{inspect(attrs[:name] || attrs["name"])}: #{inspect(errors)}")
          end
      end
    end)

    step_by_name = Map.new(ExCalibur.Quests.list_steps(), &{&1.name, &1.id})

    steps =
      (template.quest_definition || %{steps: []}).steps
      |> Kernel.||([])
      |> Enum.map(fn step ->
        resolved_id = Map.get(step_by_name, step["step_name"])

        if !resolved_id do
          Logger.warning(
            "[Board] Could not resolve step \"#{step["step_name"]}\" for template #{template.id} — step missing from DB"
          )
        end

        %{"step_id" => resolved_id, "flow" => step["flow"]}
      end)
      |> Enum.reject(fn step -> is_nil(step["step_id"]) end)

    result =
      if template.quest_definition do
        ExCalibur.Quests.create_quest(Map.put(template.quest_definition, :steps, steps))
      else
        {:ok, nil}
      end

    Enum.each(template.extra_quests || [], fn quest_def ->
      quest_steps =
        (quest_def.steps || [])
        |> Enum.map(fn step ->
          %{"step_id" => Map.get(step_by_name, step["step_name"]), "flow" => step["flow"]}
        end)
        |> Enum.reject(fn step -> is_nil(step["step_id"]) end)

      attrs = Map.put(quest_def, :steps, quest_steps)

      case ExCalibur.Quests.create_quest(attrs) do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          if Enum.any?(changeset.errors, fn {field, {_, opts}} ->
               field == :name && opts[:constraint] == :unique
             end) do
            Logger.debug("[Board] Quest already exists: #{quest_def.name}")
          else
            Logger.warning("[Board] Failed to create quest #{quest_def.name}: #{inspect(changeset_errors(changeset))}")
          end
      end
    end)

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

  @doc """
  One-click install: creates the quest + steps and auto-recruits any
  missing members mentioned in the template's suggested_team.
  """
  def recruit_and_go(%__MODULE__{} = template) do
    case install(template) do
      {:ok, quest} ->
        recruited = auto_recruit_members(template)
        {:ok, %{quest: quest, steps_created: template.step_definitions || [], members_recruited: recruited}}

      error ->
        error
    end
  end

  defp auto_recruit_members(%{suggested_team: nil}), do: []
  defp auto_recruit_members(%{suggested_team: ""}), do: []

  defp auto_recruit_members(%{suggested_team: team_desc}) do
    existing = Member |> Repo.all() |> Enum.map(& &1.name)
    team_lower = String.downcase(team_desc)

    ExCalibur.Members.BuiltinMember.all()
    |> Enum.filter(fn m ->
      String.contains?(team_lower, String.downcase(m.name)) and m.name not in existing
    end)
    |> Enum.map(fn member ->
      rank_config = member.ranks[:journeyman] || member.ranks[:apprentice] || %{}

      case Repo.insert(
             Member.changeset(%Member{}, %{
               type: "role",
               name: member.name,
               status: "active",
               source: "db",
               config: %{
                 "member_id" => member.id,
                 "system_prompt" => member.system_prompt,
                 "rank" => "journeyman",
                 "model" => rank_config[:model] || "llama3.2",
                 "strategy" => rank_config[:strategy] || "cot"
               }
             }),
             on_conflict: :nothing
           ) do
        {:ok, _} -> member.name
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc false
  def changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp humanize(str), do: str |> String.replace("_", " ") |> String.capitalize()

  defp template_id_to_quest_prefix("everyday_council"), do: "Everyday Council"
  defp template_id_to_quest_prefix(id), do: humanize(id)

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
