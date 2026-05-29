defmodule Seed.ATN.PredictionContextTest do
  use ExUnit.Case, async: true
  doctest Seed.ATN.PredictionContext

  alias Seed.ATN.PredictionContext

  test "empty/0 is the empty context" do
    assert PredictionContext.empty() == :empty
    assert PredictionContext.empty?(:empty)
  end

  test "singleton/2 pushes a return state onto a parent" do
    ctx = PredictionContext.singleton(:empty, 7)

    assert %PredictionContext{parent: :empty, return_state: 7} = ctx
    refute PredictionContext.empty?(ctx)
  end

  test "singleton/2 collapses the empty sentinel to the empty context" do
    assert PredictionContext.singleton(:empty, PredictionContext.empty_return_state()) == :empty
  end

  test "equal singletons compare equal" do
    assert PredictionContext.singleton(:empty, 3) == PredictionContext.singleton(:empty, 3)
    refute PredictionContext.singleton(:empty, 3) == PredictionContext.singleton(:empty, 4)
  end
end
