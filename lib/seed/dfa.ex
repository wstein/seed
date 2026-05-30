defmodule Seed.DFA do
  @moduledoc """
  A persisted DFA layered on the `Seed.DFACache` ETS table, after ANTLR's
  `DFA`/`DFAState`.

  Adaptive prediction visits the same configuration sets repeatedly. Keying
  the reach cache by the config set (and re-resolving it each visit) allocates
  on every warm step. This module *interns* a config set to a stable integer
  id once, so the prediction loop can then walk the decision by integer
  `edge/4` lookups — no config-list key building, no list hashing — and cache
  each state's resolution alongside it.

  Everything is keyed by the grammar's `cache_key` (so grammars never collide)
  and the SLL/LL mode bit, mirroring the existing cache. The store degrades to
  no-ops when the cache table is absent: `intern/2` returns `nil` and the
  caller keeps using the config-set path. Concurrency races only cost sharing,
  never correctness — the DFA is a pure optimization over recomputation.
  """

  alias Seed.ATN.ATNConfig
  alias Seed.DFACache

  @typedoc "A stable integer id for an interned configuration set."
  @type state_id :: non_neg_integer()

  @typedoc """
  An edge target: another state, or `:empty` (the reach is empty — a cached
  no-viable transition the caller resolves with the source state).
  """
  @type edge_target :: state_id() | :empty

  @doc """
  Interns `configs` under `cache_key`, returning its stable id (allocating one
  on first sight), or `nil` when the cache table is absent.

  The `reaches_into_outer_context` dip counter is normalized out of the
  identity: two sets that differ only in how many times a config dipped are the
  same DFA state (the dip is captured as a boolean elsewhere).
  """
  @spec intern(integer() | nil, [ATNConfig.t()]) :: state_id() | nil
  def intern(cache_key, configs) do
    with_table(nil, fn table ->
      canonical = Enum.map(configs, &%{&1 | reaches_into_outer_context: 0})
      id_key = {cache_key, :dfa_id, canonical}

      case :ets.lookup(table, id_key) do
        [{^id_key, id}] -> id
        [] -> allocate(table, cache_key, id_key, configs)
      end
    end)
  end

  @doc "Returns the config set for an interned id, or `nil`."
  @spec configs(integer() | nil, state_id()) :: [ATNConfig.t()] | nil
  def configs(cache_key, id) do
    with_table(nil, fn table ->
      case :ets.lookup(table, {cache_key, :dfa_configs, id}) do
        [{_key, configs}] -> configs
        [] -> nil
      end
    end)
  end

  @doc "Returns the target of the edge from `id` on `token`, or `nil` if none is recorded."
  @spec edge(integer() | nil, state_id(), integer(), boolean()) :: edge_target() | nil
  def edge(cache_key, id, token, full_ctx?) do
    with_table(nil, fn table ->
      case :ets.lookup(table, {cache_key, :dfa_edge, id, token, full_ctx?}) do
        [{_key, target}] -> target
        [] -> nil
      end
    end)
  end

  @doc "Records the edge from `id` on `token` to `target` (a state id or `:empty`)."
  @spec put_edge(integer() | nil, state_id(), integer(), boolean(), edge_target()) :: :ok
  def put_edge(cache_key, id, token, full_ctx?, target_id) do
    with_table(:ok, fn table ->
      :ets.insert(table, {{cache_key, :dfa_edge, id, token, full_ctx?}, target_id})
      :ok
    end)
  end

  @doc """
  Returns the cached resolution for state `id` in `full_ctx?` mode, or `nil`.

  A resolution is `{:accept, alt}` (a unique alternative), `:conflict`, or
  `:continue`; it is computed once by `put_prediction/4`.
  """
  @spec prediction(integer() | nil, state_id(), boolean()) ::
          {:accept, pos_integer()} | :conflict | :continue | nil
  def prediction(cache_key, id, full_ctx?) do
    with_table(nil, fn table ->
      case :ets.lookup(table, {cache_key, :dfa_pred, id, full_ctx?}) do
        [{_key, prediction}] -> prediction
        [] -> nil
      end
    end)
  end

  @doc "Caches the resolution `prediction` for state `id` in `full_ctx?` mode."
  @spec put_prediction(
          integer() | nil,
          state_id(),
          boolean(),
          {:accept, pos_integer()} | :conflict | :continue
        ) :: :ok
  def put_prediction(cache_key, id, full_ctx?, prediction) do
    with_table(:ok, fn table ->
      :ets.insert(table, {{cache_key, :dfa_pred, id, full_ctx?}, prediction})
      :ok
    end)
  end

  # --- internal -----------------------------------------------------------

  defp allocate(table, cache_key, id_key, configs) do
    seq = {cache_key, :dfa_seq}
    id = :ets.update_counter(table, seq, {2, 1}, {seq, 0})

    if :ets.insert_new(table, {id_key, id}) do
      :ets.insert(table, {{cache_key, :dfa_configs, id}, configs})
      id
    else
      # Lost the race; adopt the winner's id.
      [{^id_key, winner}] = :ets.lookup(table, id_key)
      winner
    end
  end

  defp with_table(absent, fun) do
    case DFACache.table() do
      nil -> absent
      table -> fun.(table)
    end
  end
end
