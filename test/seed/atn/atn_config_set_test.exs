defmodule Seed.ATN.ATNConfigSetTest do
  use ExUnit.Case, async: true

  alias Seed.ATN.ATNConfig
  alias Seed.ATN.ATNConfigSet
  alias Seed.ATN.LexerAction
  alias Seed.ATN.LexerActionExecutor
  alias Seed.ATN.PredictionContext

  defp config(state, alt, opts \\ []) do
    %ATNConfig{
      state: state,
      alt: alt,
      context: Keyword.get(opts, :context, :empty),
      lexer_action_executor: Keyword.get(opts, :executor),
      passed_through_non_greedy: Keyword.get(opts, :non_greedy, false)
    }
  end

  describe "add/2" do
    test "preserves insertion order" do
      set =
        ATNConfigSet.new()
        |> ATNConfigSet.add(config(1, 1))
        |> ATNConfigSet.add(config(2, 2))
        |> ATNConfigSet.add(config(3, 3))

      assert Enum.map(ATNConfigSet.configs(set), & &1.state) == [1, 2, 3]
    end

    test "drops a fully equal config" do
      set =
        ATNConfigSet.new()
        |> ATNConfigSet.add(config(1, 1))
        |> ATNConfigSet.add(config(1, 1))

      assert length(ATNConfigSet.configs(set)) == 1
    end

    test "keeps configs that differ only by context" do
      set =
        ATNConfigSet.new()
        |> ATNConfigSet.add(config(1, 1, context: :empty))
        |> ATNConfigSet.add(config(1, 1, context: PredictionContext.singleton(:empty, 5)))

      assert length(ATNConfigSet.configs(set)) == 2
    end

    test "keeps configs that differ only by accumulated actions" do
      executor = LexerActionExecutor.append(nil, %LexerAction{type: :skip})

      set =
        ATNConfigSet.new()
        |> ATNConfigSet.add(config(1, 1))
        |> ATNConfigSet.add(config(1, 1, executor: executor))

      assert length(ATNConfigSet.configs(set)) == 2
    end
  end

  describe "empty?/1" do
    test "is true for a fresh set" do
      assert ATNConfigSet.empty?(ATNConfigSet.new())
    end

    test "is false after an add" do
      refute ATNConfigSet.new() |> ATNConfigSet.add(config(1, 1)) |> ATNConfigSet.empty?()
    end
  end
end
