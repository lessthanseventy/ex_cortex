defmodule ExCalibur.Board do
  @moduledoc """
  Pre-configured quest templates for the Quest Board.

  Templates are organized by category and declare hard requirements
  (source types and herald types that must be configured) so the UI
  can show which quests are ready to install today.
  """

  import Ecto.Query

  alias ExCalibur.Heralds.Herald
  alias ExCalibur.Quests.Quest
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
            from(q in Quest,
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
  Like all/0 but annotates each template with requirements and readiness using
  batched DB queries — O(4) queries for any number of templates instead of O(N*M).
  Returns list of %{template, requirements, readiness} maps.
  """
  def all_with_status do
    templates = all()

    source_types = flat_requirements(templates, :source_type)
    herald_types = flat_requirements(templates, :herald_type)
    not_installed_ids = flat_requirements(templates, :not_installed)
    needs_members = Enum.any?(templates, &(:any_members in (&1.requires || [])))

    present_source_types = fetch_present_source_types(source_types)
    present_herald_types = fetch_present_herald_types(herald_types)

    has_active_members =
      needs_members && Repo.exists?(from(m in Member, where: m.type == "role" and m.status == "active"))

    installed_prefixes = fetch_installed_prefixes(not_installed_ids)

    Enum.map(templates, fn template ->
      reqs =
        check_requirements_batched(
          template,
          present_source_types,
          present_herald_types,
          has_active_members,
          installed_prefixes
        )

      missing = Enum.count(reqs, fn {met, _} -> !met end)
      readiness = compute_readiness(reqs, missing)
      %{template: template, requirements: reqs, readiness: readiness}
    end)
  end

  defp fetch_present_source_types([]), do: MapSet.new()

  defp fetch_present_source_types(source_types) do
    from(s in Source, where: s.source_type in ^source_types and s.status in ["active", "paused"], select: s.source_type)
    |> Repo.all()
    |> MapSet.new()
  end

  defp fetch_present_herald_types([]), do: MapSet.new()

  defp fetch_present_herald_types(herald_types) do
    from(h in Herald, where: h.type in ^herald_types, select: h.type)
    |> Repo.all()
    |> MapSet.new()
  end

  defp fetch_installed_prefixes([]), do: MapSet.new()

  defp fetch_installed_prefixes(not_installed_ids) do
    prefixes = Enum.map(not_installed_ids, &template_id_to_quest_prefix/1)
    quest_names = Repo.all(from(q in Quest, where: q.status in ["active", "paused"], select: q.name))

    prefixes
    |> Enum.filter(fn prefix -> Enum.any?(quest_names, &String.contains?(&1, prefix)) end)
    |> MapSet.new()
  end

  defp check_requirements_batched(
         template,
         present_source_types,
         present_herald_types,
         has_active_members,
         installed_prefixes
       ) do
    Enum.map(template.requires || [], fn
      {:source_type, type} ->
        {MapSet.member?(present_source_types, type), "#{humanize(type)} source"}

      {:herald_type, type} ->
        {MapSet.member?(present_herald_types, type), "#{humanize(type)} herald"}

      :any_members ->
        {has_active_members, "Active members"}

      {:not_installed, id} ->
        {!MapSet.member?(installed_prefixes, template_id_to_quest_prefix(id)), "Not included in #{humanize(id)}"}
    end)
  end

  defp compute_readiness([], _missing), do: :ready
  defp compute_readiness(_reqs, 0), do: :ready
  defp compute_readiness(_reqs, 1), do: :almost
  defp compute_readiness(_reqs, _), do: :unavailable

  defp flat_requirements(templates, type) do
    templates
    |> Enum.flat_map(fn t ->
      t.requires
      |> Kernel.||([])
      |> Enum.filter(&match?({^type, _}, &1))
      |> Enum.map(fn {_, v} -> v end)
    end)
    |> Enum.uniq()
  end

  @doc """
  Install a template: creates its steps and quest.
  Returns {:ok, quest} or {:error, reason}.
  """
  def install(%__MODULE__{} = template) do
    require Logger

    Enum.each(template.step_definitions || [], &install_step/1)

    step_by_name = Map.new(ExCalibur.Quests.list_steps(), &{&1.name, &1.id})

    result = install_main_quest(template, step_by_name)

    Enum.each(template.extra_quests || [], &install_extra_quest(&1, step_by_name))
    Enum.each(template.source_definitions || [], &install_source/1)

    result
  end

  defp install_step(attrs) do
    require Logger

    case ExCalibur.Quests.create_step(attrs) do
      {:ok, step} ->
        Logger.debug("[Board] Created step #{step.id} (#{step.name})")

      {:error, changeset} ->
        if unique_name_conflict?(changeset) do
          Logger.debug("[Board] Step already exists: #{attrs[:name] || attrs["name"]}")
        else
          Logger.warning(
            "[Board] Failed to create step #{inspect(attrs[:name] || attrs["name"])}: #{inspect(changeset_errors(changeset))}"
          )
        end
    end
  end

  defp install_main_quest(%{quest_definition: nil}, _step_by_name), do: {:ok, nil}

  defp install_main_quest(%{quest_definition: quest_def, id: template_id} = _template, step_by_name) do
    require Logger

    steps =
      (quest_def.steps || [])
      |> Enum.map(fn step ->
        resolved_id = Map.get(step_by_name, step["step_name"])

        if !resolved_id do
          Logger.warning(
            "[Board] Could not resolve step \"#{step["step_name"]}\" for template #{template_id} — step missing from DB"
          )
        end

        %{"step_id" => resolved_id, "flow" => step["flow"]}
      end)
      |> Enum.reject(&is_nil(&1["step_id"]))

    ExCalibur.Quests.create_quest(Map.put(quest_def, :steps, steps))
  end

  defp install_extra_quest(quest_def, step_by_name) do
    require Logger

    quest_steps =
      (quest_def.steps || [])
      |> Enum.map(fn step ->
        %{"step_id" => Map.get(step_by_name, step["step_name"]), "flow" => step["flow"]}
      end)
      |> Enum.reject(&is_nil(&1["step_id"]))

    case ExCalibur.Quests.create_quest(Map.put(quest_def, :steps, quest_steps)) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        if unique_name_conflict?(changeset) do
          Logger.debug("[Board] Quest already exists: #{quest_def.name}")
        else
          Logger.warning("[Board] Failed to create quest #{quest_def.name}: #{inspect(changeset_errors(changeset))}")
        end
    end
  end

  defp install_source(source_def) do
    exists =
      Repo.exists?(from(s in Source, where: s.name == ^source_def.name and s.source_type == ^source_def.source_type))

    if !exists do
      Repo.insert(%Source{
        name: source_def.name,
        source_type: source_def.source_type,
        config: source_def.config,
        status: "active",
        book_id: source_def[:book_id]
      })
    end
  end

  defp unique_name_conflict?(changeset) do
    Enum.any?(changeset.errors, fn {field, {_, opts}} ->
      field == :name && opts[:constraint] == :unique
    end)
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
