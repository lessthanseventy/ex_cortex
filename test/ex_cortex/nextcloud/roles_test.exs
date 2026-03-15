defmodule ExCortex.Nextcloud.RolesTest do
  use ExUnit.Case, async: true

  alias ExCortex.Nextcloud.Roles

  describe "role_for/1" do
    test "returns configured role for known user" do
      assert Roles.role_for("admin") == :super_admin
    end

    test "returns :user for unknown users" do
      assert Roles.role_for("random_person") == :user
    end
  end

  describe "super_admin?/1" do
    test "admin is super_admin" do
      assert Roles.super_admin?("admin")
    end

    test "unknown user is not super_admin" do
      refute Roles.super_admin?("random")
    end
  end

  describe "admin?/1" do
    test "super_admin counts as admin" do
      assert Roles.admin?("admin")
    end
  end

  describe "can?/2" do
    test "super_admin can do anything" do
      assert Roles.can?("admin", :manage_system)
      assert Roles.can?("admin", :manage_guilds)
      assert Roles.can?("admin", :run_quests)
    end

    test "user can view and run thoughts" do
      assert Roles.can?("random", :view_all)
      assert Roles.can?("random", :run_quests)
    end

    test "user cannot manage system" do
      refute Roles.can?("random", :manage_system)
      refute Roles.can?("random", :manage_guilds)
    end
  end
end
