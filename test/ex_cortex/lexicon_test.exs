defmodule ExCortex.LexiconTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Lexicon

  test "get_axiom_by_name returns axiom when found" do
    {:ok, _} = Lexicon.create_axiom(%{name: "test_axiom", content: "hello"})
    axiom = Lexicon.get_axiom_by_name("test_axiom")
    assert axiom.name == "test_axiom"
  end

  test "get_axiom_by_name returns nil when not found" do
    assert Lexicon.get_axiom_by_name("nope") == nil
  end
end
