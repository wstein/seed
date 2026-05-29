defmodule Seed.DFACacheTest do
  # Not async: the cache is a shared ETS table.
  use ExUnit.Case, async: false

  alias Seed.DFACache

  test "memoize/2 computes on a miss and returns the cached value on a hit" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    compute = fn -> Agent.get_and_update(counter, &{:value, &1 + 1}) end
    key = {:dfa_cache_test, :compute_once}

    assert DFACache.memoize(key, compute) == :value
    assert DFACache.memoize(key, compute) == :value
    assert Agent.get(counter, & &1) == 1
  end

  test "clear/0 drops cached entries so the value is recomputed" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    compute = fn -> Agent.get_and_update(counter, &{:value, &1 + 1}) end
    key = {:dfa_cache_test, :recompute_after_clear}

    DFACache.memoize(key, compute)
    DFACache.clear()
    DFACache.memoize(key, compute)

    assert Agent.get(counter, & &1) == 2
  end
end
