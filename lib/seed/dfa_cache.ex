defmodule Seed.DFACache do
  @moduledoc """
  A process-owned, bounded ETS cache for ATN-simulation decisions.

  The ATN simulators recompute the same epsilon-closures repeatedly; this
  memoizes them across parses, implementing the ADR-005 decision to hold the
  adaptive cache in ETS. The cache is a pure performance optimization — a
  miss simply recomputes, and the accessors degrade to no-ops when the table
  is absent, so the simulators work with or without the cache running.

  Design decisions (see ADR-005):

    * **Ownership** — this GenServer owns a `:public` `:named_table`, so it
      outlives any single parse and callers read and write it directly with
      no message round-trip.
    * **Keys** — entries are keyed including the ATN's `cache_key` (a hash of
      the serialized grammar), so different grammars never collide.
    * **Bound** — the table is capped and cleared wholesale on overflow, a
      simple, safe guard against unbounded growth on adversarial input.
  """

  use GenServer

  @table :seed_dfa_cache
  @max_entries 100_000

  @doc "Starts the cache owner."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Returns the cached value for `key`, computing and storing it on a miss.

  When the cache table is absent, simply computes the value.
  """
  @spec memoize(term(), (-> value)) :: value when value: term()
  def memoize(key, compute) do
    case :ets.whereis(@table) do
      :undefined -> compute.()
      table -> lookup_or_compute(table, key, compute)
    end
  end

  @doc """
  Returns the live ETS table name, or `nil` when the cache is not running.

  `Seed.DFA` stores its interned states and edges in this table directly, so
  it shares the cache's ownership and wholesale-clear-on-overflow guard.
  """
  @spec table() :: atom() | nil
  def table do
    case :ets.whereis(@table) do
      :undefined -> nil
      _ref -> @table
    end
  end

  @doc "Removes all cached entries."
  @spec clear() :: :ok
  def clear do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      table ->
        :ets.delete_all_objects(table)
        :ok
    end
  end

  @impl true
  def init(_opts) do
    _table =
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, :no_state}
  end

  defp lookup_or_compute(table, key, compute) do
    case :ets.lookup(table, key) do
      [{^key, value}] ->
        value

      [] ->
        if :ets.info(table, :size) >= @max_entries, do: :ets.delete_all_objects(table)
        value = compute.()
        :ets.insert(table, {key, value})
        value
    end
  end
end
