defmodule Seed.IntervalSetTest do
  use ExUnit.Case, async: true
  doctest Seed.IntervalSet

  alias Seed.IntervalSet

  describe "add_range/3 and member?/2" do
    test "stores an inclusive range" do
      set = IntervalSet.new() |> IntervalSet.add_range(3, 6)

      refute IntervalSet.member?(set, 2)
      assert IntervalSet.member?(set, 3)
      assert IntervalSet.member?(set, 6)
      refute IntervalSet.member?(set, 7)
    end

    test "ignores an inverted range" do
      set = IntervalSet.new() |> IntervalSet.add_range(6, 3)
      assert IntervalSet.intervals(set) == []
    end
  end

  describe "merging" do
    test "coalesces overlapping ranges" do
      set =
        IntervalSet.new()
        |> IntervalSet.add_range(1, 5)
        |> IntervalSet.add_range(4, 8)

      assert IntervalSet.intervals(set) == [{1, 8}]
    end

    test "coalesces adjacent ranges" do
      set =
        IntervalSet.new()
        |> IntervalSet.add_range(1, 3)
        |> IntervalSet.add_range(4, 6)

      assert IntervalSet.intervals(set) == [{1, 6}]
    end

    test "keeps disjoint ranges separate and sorted" do
      set =
        IntervalSet.new()
        |> IntervalSet.add_range(10, 12)
        |> IntervalSet.add_range(1, 3)

      assert IntervalSet.intervals(set) == [{1, 3}, {10, 12}]
    end
  end

  describe "add_one/2" do
    test "adds a single value, including EOF (-1)" do
      set = IntervalSet.new() |> IntervalSet.add_one(-1)

      assert IntervalSet.member?(set, -1)
      assert IntervalSet.intervals(set) == [{-1, -1}]
    end
  end
end
