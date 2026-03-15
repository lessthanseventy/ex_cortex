defmodule ExCortex.Settings do
  @moduledoc "App-wide settings (single-row table)."

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  @valid_banners ~w(tech lifestyle business)

  schema "settings" do
    field :banner, :string
    field :config, :map, default: %{}

    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:banner, :config])
    |> validate_inclusion(:banner, [nil | @valid_banners])
  end

  def get_banner do
    case ExCortex.Repo.one(__MODULE__) do
      nil -> nil
      settings -> settings.banner
    end
  end

  def set_banner(banner) do
    case_result =
      case ExCortex.Repo.one(__MODULE__) do
        nil -> %__MODULE__{}
        existing -> existing
      end

    case_result
    |> changeset(%{banner: banner})
    |> ExCortex.Repo.insert_or_update()
  end

  def get_all do
    case ExCortex.Repo.one(from(s in __MODULE__)) do
      nil -> %{}
      setting -> setting.config || %{}
    end
  end

  def get(key) when is_atom(key) do
    case ExCortex.Repo.one(from(s in __MODULE__)) do
      nil -> nil
      setting -> get_in(setting.config || %{}, [Atom.to_string(key)])
    end
  end

  def put(key, value) when is_atom(key) do
    setting = ExCortex.Repo.one(from(s in __MODULE__)) || %__MODULE__{}
    config = Map.put(setting.config || %{}, Atom.to_string(key), value)

    setting
    |> changeset(%{config: config})
    |> ExCortex.Repo.insert_or_update()
  end

  @doc """
  Get a setting from DB first, then fall back to Application env, then env var.
  This is the primary way LLM modules should read config — it makes Instinct
  settings take effect without a restart.
  """
  def resolve(key, opts \\ []) do
    app_key = Keyword.get(opts, :app_key, key)
    env_var = Keyword.get(opts, :env_var)
    default = Keyword.get(opts, :default)

    db_value =
      try do
        get(key)
      rescue
        _ -> nil
      end

    db_value
    |> fallback(fn -> Application.get_env(:ex_cortex, app_key) end)
    |> fallback(fn -> if env_var, do: System.get_env(env_var) end)
    |> fallback(fn -> default end)
  end

  @doc """
  Sync DB settings into Application env so libraries like ReqLLM pick them up.
  Called at boot and after Instinct saves.
  """
  def apply_to_runtime do
    config = get_all()

    if url = config["ollama_url"], do: Application.put_env(:ex_cortex, :ollama_url, url)
    if key = config["ollama_api_key"], do: Application.put_env(:ex_cortex, :ollama_api_key, key)

    if key = config["anthropic_api_key"] do
      Application.put_env(:ex_cortex, :anthropic_api_key, key)
      Application.put_env(:req_llm, :anthropic_api_key, key)
    end
  rescue
    # DB might not be up yet during boot
    _ -> :ok
  end

  defp fallback(nil, fun), do: fun.()
  defp fallback("", fun), do: fun.()
  defp fallback(value, _fun), do: value
end
