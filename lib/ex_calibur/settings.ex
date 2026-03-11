defmodule ExCalibur.Settings do
  @moduledoc "App-wide settings (single-row table)."

  use Ecto.Schema

  import Ecto.Changeset

  @valid_banners ~w(tech lifestyle business)

  schema "settings" do
    field :banner, :string

    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:banner])
    |> validate_inclusion(:banner, @valid_banners)
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
end
