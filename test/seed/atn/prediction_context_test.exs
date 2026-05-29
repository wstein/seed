defmodule Seed.ATN.PredictionContextTest do
  use ExUnit.Case, async: true
  doctest Seed.ATN.PredictionContext

  alias Seed.ATN.PredictionContext, as: PC
  alias Seed.ATN.PredictionContext.Array

  @full false
  @sll true

  test "empty/0 is the empty context" do
    assert PC.empty() == :empty
    assert PC.empty?(:empty)
    refute PC.empty?(PC.singleton(:empty, 7))
  end

  test "singleton/2 pushes and collapses the empty sentinel" do
    assert %PC{parent: :empty, return_state: 7} = PC.singleton(:empty, 7)
    assert PC.singleton(:empty, PC.empty_return_state()) == :empty
  end

  describe "accessors" do
    test "report size, return state, and parent for each form" do
      singleton = PC.singleton(:empty, 5)
      array = %Array{parents: [:empty, nil], return_states: [5, PC.empty_return_state()]}

      assert PC.size(:empty) == 1
      assert PC.size(singleton) == 1
      assert PC.size(array) == 2
      assert PC.return_state(singleton, 0) == 5
      assert PC.parent(singleton, 0) == :empty
      assert PC.return_state(array, 1) == PC.empty_return_state()
      assert PC.has_empty_path?(array)
      refute PC.has_empty_path?(singleton)
    end
  end

  describe "merge/3" do
    test "equal contexts merge to themselves" do
      ctx = PC.singleton(:empty, 9)
      assert PC.merge(ctx, ctx, @full) == ctx
    end

    test "SLL: the empty context is a wildcard that absorbs the other" do
      assert PC.merge(:empty, PC.singleton(:empty, 4), @sll) == :empty
      assert PC.merge(PC.singleton(:empty, 4), :empty, @sll) == :empty
    end

    test "full LL: empty merges into a distinct $ stack" do
      merged = PC.merge(:empty, PC.singleton(:empty, 4), @full)
      assert %Array{parents: [:empty, nil], return_states: [4, max]} = merged
      assert max == PC.empty_return_state()
    end

    test "singletons with the same return state merge their parents" do
      a = PC.singleton(:empty, 4)
      assert PC.merge(a, PC.singleton(:empty, 4), @full) == a
    end

    test "singletons with different return states form a sorted array" do
      a = PC.singleton(:empty, 7)
      b = PC.singleton(:empty, 3)

      assert %Array{parents: [:empty, :empty], return_states: [3, 7]} = PC.merge(a, b, @full)
    end

    test "arrays merge by return state, keeping sorted order" do
      a = %Array{parents: [:empty, :empty], return_states: [1, 5]}
      b = %Array{parents: [:empty, :empty], return_states: [3, 5]}

      assert %Array{return_states: [1, 3, 5]} = PC.merge(a, b, @full)
    end

    test "a single-element merged array reduces back to a singleton" do
      # Same return state, different parents: merges to one slot, so the
      # array result reduces to a singleton (whose parent is the merge).
      a = %Array{parents: [PC.singleton(:empty, 1)], return_states: [5]}
      b = %Array{parents: [PC.singleton(:empty, 2)], return_states: [5]}

      assert %PC{return_state: 5, parent: %Array{return_states: [1, 2]}} = PC.merge(a, b, @full)
    end
  end
end
