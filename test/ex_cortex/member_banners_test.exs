defmodule ExCortex.MemberBannersTest do
  use ExUnit.Case, async: true

  alias ExCortex.Neurons.Builtin

  describe "builtin neuron lobes" do
    test "all neurons have a lobe tag" do
      for neuron <- Builtin.all() do
        assert neuron.lobe in [:frontal, :parietal, :limbic, :cerebellar, :temporal, :occipital],
               "Neuron #{neuron.id} missing lobe tag"
      end
    end

    test "filter_by_lobe/1 returns matching neurons" do
      tech = Builtin.filter_by_lobe(:frontal)
      assert tech != []
      assert Enum.all?(tech, &(&1.lobe == :frontal))
    end
  end
end
