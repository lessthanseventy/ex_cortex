defmodule ExCortex.Nextcloud.Roles do
  @moduledoc """
  Maps Nextcloud users to ExCortex roles.

  Roles:
  - super_admin: Full access, can modify system settings and manage all clusters
  - admin: Can manage clusters, run thoughts, and view all data
  - user: Can view dashboards and run limited thoughts
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
    case Application.get_env(:ex_cortex, :nextcloud_roles) do
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

  defp check_permission(:admin, action) when action in [:manage_clusters, :run_thoughts, :view_all, :manage_sources],
    do: true

  defp check_permission(:admin, :manage_system), do: false

  defp check_permission(:user, action) when action in [:view_all, :run_thoughts], do: true

  defp check_permission(_role, _action), do: false
end
