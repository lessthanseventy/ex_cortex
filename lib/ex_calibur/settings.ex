defmodule ExCalibur.Settings do
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
    case ExCalibur.Repo.one(__MODULE__) do
      nil -> nil
      settings -> settings.banner
    end
  end

  def set_banner(banner) do
    case_result =
      case ExCalibur.Repo.one(__MODULE__) do
        nil -> %__MODULE__{}
        existing -> existing
      end

    case_result
    |> changeset(%{banner: banner})
    |> ExCalibur.Repo.insert_or_update()
  end

  def get_all do
    case ExCalibur.Repo.one(from(s in __MODULE__)) do
      nil -> %{}
      setting -> setting.config || %{}
    end
  end

  def get(key) when is_atom(key) do
    case ExCalibur.Repo.one(from(s in __MODULE__)) do
      nil -> nil
      setting -> get_in(setting.config || %{}, [Atom.to_string(key)])
    end
  end

  def put(key, value) when is_atom(key) do
    setting = ExCalibur.Repo.one(from(s in __MODULE__)) || %__MODULE__{}
    config = Map.put(setting.config || %{}, Atom.to_string(key), value)

    setting
    |> changeset(%{config: config})
    |> ExCalibur.Repo.insert_or_update()
  end
end
