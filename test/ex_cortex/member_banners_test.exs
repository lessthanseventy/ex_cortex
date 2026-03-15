defmodule ExCortex.MemberBannersTest do
  use ExUnit.Case, async: true

  alias ExCortex.Neurons.Builtin

  describe "builtin neuron banners" do
    test "all neurons have a banner tag" do
      for neuron <- Builtin.all() do
        assert neuron.banner in [:tech, :lifestyle, :business],
               "Neuron #{neuron.id} missing banner tag"
      end
    end

    test "filter_by_banner/1 returns matching neurons" do
      tech = Builtin.filter_by_banner(:tech)
      assert tech != []
      assert Enum.all?(tech, &(&1.banner == :tech))
    end
  end
end
