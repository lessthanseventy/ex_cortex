defmodule ExCalibur.Nextcloud.Roles do
  @moduledoc """
  Maps Nextcloud users to ExCalibur roles.

  Roles:
  - super_admin: Full access, can modify system settings and manage all guilds
  - admin: Can manage guilds, run quests, and view all data
  - user: Can view dashboards and run limited quests
  """

  @default_roles %{
    "admin" => :super_admin
  }

  def role_for(username) do
    roles = configured_roles()
    Map.get(roles, username, :user)
  end

  def super_admin?(username), do: role_for(username) == :super_admin
  def admin?(username), do: role_for(username) in [:super_admin, :admin]

  def configured_roles do
    case Application.get_env(:ex_calibur, :nextcloud_roles) do
      nil -> @default_roles
      roles when is_map(roles) -> roles
      _ -> @default_roles
    end
  end

  def can?(username, action) do
    role = role_for(username)
    check_permission(role, action)
  end

  defp check_permission(:super_admin, _action), do: true

  defp check_permission(:admin, action) when action in [:manage_guilds, :run_quests, :view_all, :manage_sources], do: true

  defp check_permission(:admin, :manage_system), do: false

  defp check_permission(:user, action) when action in [:view_all, :run_quests], do: true

  defp check_permission(_role, _action), do: false
end
