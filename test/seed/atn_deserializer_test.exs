defmodule Seed.ATNDeserializerTest do
  use ExUnit.Case, async: true
  doctest Seed.ATNDeserializer

  alias Seed.ATN
  alias Seed.ATNDeserializer

  @fixtures_dir Path.expand("../fixtures/atn", __DIR__)
  @fixtures ~w(hello_parser hello_lexer expr_parser expr_lexer cover_parser cover_lexer)

  describe "deserialize/1 error handling" do
    test "rejects an unsupported serialization version" do
      assert {:error, {:unsupported_version, 3}} = ATNDeserializer.deserialize([3, 1, 0, 0])
    end

    test "reports a stream that is not fully consumed" do
      # A valid empty parser ATN (11 ints) followed by a trailing int.
      assert {:error, {:unconsumed, 11, 12}} =
               ATNDeserializer.deserialize([4, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 99])
    end

    test "deserialize!/1 raises on a bad version" do
      assert_raise ArgumentError, fn -> ATNDeserializer.deserialize!([3, 1, 0, 0]) end
    end
  end

  # Validate every fixture against the reference oracle produced by the
  # canonical ANTLR4 runtime (see test/fixtures/atn/README.md).
  for name <- @fixtures do
    test "#{name}: grammar type and structural counts match the oracle" do
      name = unquote(name)
      atn = load_atn(name)
      oracle = load_oracle(name)

      assert atn.grammar_type |> Atom.to_string() |> String.upcase() == oracle["grammarType"]
      assert atn.max_token_type == oracle["maxTokenType"]
      assert ATN.num_states(atn) == oracle["numStates"]
      assert ATN.num_rules(atn) == oracle["numRules"]
      assert ATN.num_decisions(atn) == oracle["numDecisions"]
      assert ATN.num_modes(atn) == oracle["numModes"]
    end

    test "#{name}: state-type histogram matches the oracle" do
      name = unquote(name)
      atn = load_atn(name)
      oracle = load_oracle(name)

      assert string_keys(ATN.state_type_histogram(atn)) == oracle["stateTypeHistogram"]
    end

    test "#{name}: transition-type histogram matches the oracle" do
      name = unquote(name)
      atn = load_atn(name)
      oracle = load_oracle(name)

      assert string_keys(ATN.transition_type_histogram(atn)) == oracle["transitionTypeHistogram"]
    end
  end

  test "lexer fixtures expose a token-type table; parser fixtures do not" do
    assert load_atn("hello_lexer").rule_to_token_type != nil
    assert load_atn("hello_parser").rule_to_token_type == nil
  end

  defp load_atn(name) do
    @fixtures_dir
    |> Path.join(name <> ".atn")
    |> File.read!()
    |> String.trim()
    |> String.split(",")
    |> Enum.map(&String.to_integer/1)
    |> ATNDeserializer.deserialize!()
  end

  defp load_oracle(name) do
    @fixtures_dir
    |> Path.join(name <> ".oracle.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp string_keys(histogram) do
    Map.new(histogram, fn {id, count} -> {Integer.to_string(id), count} end)
  end
end
