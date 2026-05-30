defmodule Seed.DFATest do
  use ExUnit.Case, async: true

  alias Seed.ATN.ATNConfig
  alias Seed.DFA

  # A distinct cache_key per test keeps the shared ETS table partitioned, so
  # async tests do not interfere.
  setup context do
    %{key: :erlang.phash2(context.test)}
  end

  defp cfg(state, alt, opts \\ []) do
    struct(%ATNConfig{state: state, alt: alt, context: :empty}, opts)
  end

  describe "intern/2" do
    test "assigns a stable id, equal for equal config sets", %{key: key} do
      set = [cfg(1, 1), cfg(2, 2)]
      id = DFA.intern(key, set)

      assert is_integer(id)
      assert DFA.intern(key, set) == id
    end

    test "ignores the reaches_into_outer_context dip counter in identity", %{key: key} do
      id = DFA.intern(key, [cfg(1, 1, reaches_into_outer_context: 0)])
      dipped = DFA.intern(key, [cfg(1, 1, reaches_into_outer_context: 3)])

      assert dipped == id
    end

    test "distinct config sets get distinct ids", %{key: key} do
      refute DFA.intern(key, [cfg(1, 1)]) == DFA.intern(key, [cfg(1, 2)])
    end

    test "ids are partitioned per grammar (cache_key)", %{key: key} do
      # An id allocated under one grammar resolves to its own configs even when
      # another grammar reuses the same numeric id.
      a = DFA.intern(key, [cfg(1, 1)])
      _other = DFA.intern(key + 1, [cfg(9, 9)])

      assert [%ATNConfig{state: 1, alt: 1}] = DFA.configs(key, a)
    end
  end

  describe "configs/2" do
    test "round-trips the interned config set (with its original counters)", %{key: key} do
      set = [cfg(3, 1, reaches_into_outer_context: 2)]
      id = DFA.intern(key, set)
      assert DFA.configs(key, id) == set
    end

    test "is nil for an unknown id", %{key: key} do
      assert DFA.configs(key, 999_999) == nil
    end
  end

  describe "edges" do
    test "round-trip an edge, separate per token and per mode", %{key: key} do
      a = DFA.intern(key, [cfg(1, 1)])
      b = DFA.intern(key, [cfg(2, 1)])

      assert DFA.edge(key, a, 5, false) == nil
      DFA.put_edge(key, a, 5, false, b)
      assert DFA.edge(key, a, 5, false) == b
      # different token / different mode are independent edges
      assert DFA.edge(key, a, 6, false) == nil
      assert DFA.edge(key, a, 5, true) == nil
    end
  end

  describe "prediction cache" do
    test "round-trips a resolution per state and mode", %{key: key} do
      id = DFA.intern(key, [cfg(1, 1)])

      assert DFA.prediction(key, id, false) == nil
      DFA.put_prediction(key, id, false, {:accept, 2})
      assert DFA.prediction(key, id, false) == {:accept, 2}
      assert DFA.prediction(key, id, true) == nil
    end
  end
end
