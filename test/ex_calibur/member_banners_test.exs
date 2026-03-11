defmodule ExCalibur.MemberBannersTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Members.BuiltinMember

  describe "builtin member banners" do
    test "all members have a banner tag" do
      for member <- BuiltinMember.all() do
        assert member.banner in [:tech, :lifestyle, :business],
               "Member #{member.id} missing banner tag"
      end
    end

    test "filter_by_banner/1 returns matching members" do
      tech = BuiltinMember.filter_by_banner(:tech)
      assert length(tech) > 0
      assert Enum.all?(tech, &(&1.banner == :tech))
    end
  end
end
