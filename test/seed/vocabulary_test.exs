defmodule Seed.VocabularyTest do
  use ExUnit.Case, async: true
  doctest Seed.Vocabulary

  alias Seed.Vocabulary

  describe "new/2" do
    test "indexes literal and symbolic names by token type" do
      vocab = Vocabulary.new([nil, "'if'", "'while'"], [nil, "IF", "WHILE"])

      assert Vocabulary.literal_name(vocab, 1) == "'if'"
      assert Vocabulary.literal_name(vocab, 2) == "'while'"
      assert Vocabulary.symbolic_name(vocab, 1) == "IF"
      assert Vocabulary.symbolic_name(vocab, 2) == "WHILE"
    end

    test "treats nil entries as absent" do
      vocab = Vocabulary.new([nil, nil], [nil, "IF"])

      assert Vocabulary.literal_name(vocab, 1) == nil
      assert Vocabulary.symbolic_name(vocab, 1) == "IF"
    end

    test "reports the max token type across both lists" do
      vocab = Vocabulary.new([nil, "'if'"], [nil, "IF", "WHILE", "FOR"])

      assert Vocabulary.max_token_type(vocab) == 3
    end

    test "never reports a negative max token type" do
      assert Vocabulary.max_token_type(Vocabulary.new([], [])) == 0
    end
  end

  describe "display_name/2" do
    test "prefers the literal name" do
      vocab = Vocabulary.new([nil, "'if'"], [nil, "IF"])
      assert Vocabulary.display_name(vocab, 1) == "'if'"
    end

    test "falls back to the symbolic name" do
      vocab = Vocabulary.new([nil, nil], [nil, "IF"])
      assert Vocabulary.display_name(vocab, 1) == "IF"
    end

    test "falls back to the numeric type" do
      vocab = Vocabulary.new([], [])
      assert Vocabulary.display_name(vocab, 7) == "7"
    end
  end

  describe "empty/0" do
    test "knows no names" do
      vocab = Vocabulary.empty()

      assert Vocabulary.literal_name(vocab, 1) == nil
      assert Vocabulary.symbolic_name(vocab, 1) == nil
      assert Vocabulary.display_name(vocab, 1) == "1"
    end
  end
end
