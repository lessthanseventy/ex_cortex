defmodule ExCalibur.LibraryTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Library

  test "get_dictionary_by_name returns dictionary when found" do
    {:ok, _} = Library.create_dictionary(%{name: "test_dict", content: "hello"})
    dict = Library.get_dictionary_by_name("test_dict")
    assert dict.name == "test_dict"
  end

  test "get_dictionary_by_name returns nil when not found" do
    assert Library.get_dictionary_by_name("nope") == nil
  end
end
