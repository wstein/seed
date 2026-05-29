defmodule Seed.ATNDeserializer do
  @moduledoc """
  Reconstructs a `Seed.ATN` from the serialized integer stream the ANTLR
  tool emits.

  The serialized form is the contract between the tool and Seed (see the
  ADR-002 decision in the architecture docs): a flat array of integers,
  version 4, identical across the canonical ANTLR4 tool and antlr-ng. This
  module is a faithful transliteration of the reference runtimes' decoders
  (Java, Python3, Go), reading the sections in order: header, states,
  rules, modes, interval sets, edges, decisions, and lexer actions, then
  deriving rule-stop return edges and linking block, loop, and precedence
  structure.

      iex> data = [4, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0]
      iex> {:ok, atn} = Seed.ATNDeserializer.deserialize(data)
      iex> {atn.grammar_type, atn.num_states}
      {:parser, 1}
  """

  alias Seed.ATN
  alias Seed.ATN.{LexerAction, State, Transition}
  alias Seed.IntervalSet

  @serialized_version 4

  @eof -1

  @doc """
  Deserializes `data` into a `Seed.ATN`.

  Returns `{:ok, atn}`, or `{:error, reason}` if the version is
  unsupported or the stream is malformed (a leftover or truncated stream is
  reported rather than producing a corrupt ATN).
  """
  @spec deserialize([integer()]) :: {:ok, ATN.t()} | {:error, term()}
  def deserialize(data) when is_list(data) do
    cursor = %{
      data: List.to_tuple(data),
      size: length(data),
      p: 0,
      # Stable per-grammar key for the DFA cache: identical serialized ATNs
      # (i.e. the same grammar) share cached decisions.
      cache_key: :erlang.phash2(data),
      grammar_type: nil,
      max_token_type: 0,
      states: %{},
      num_states: 0,
      rule_to_start_state: [],
      rule_to_stop_state: [],
      rule_to_token_type: nil,
      mode_to_start_state: [],
      decision_to_state: [],
      lexer_actions: [],
      sets: []
    }

    {version, cursor} = read1(cursor)

    if version == @serialized_version do
      decode(cursor)
    else
      {:error, {:unsupported_version, version}}
    end
  end

  @doc """
  Deserializes `data`, raising `ArgumentError` on failure.

  Convenience wrapper around `deserialize/1` for callers that treat a
  malformed ATN as a programmer error.
  """
  @spec deserialize!([integer()]) :: ATN.t()
  def deserialize!(data) do
    case deserialize(data) do
      {:ok, atn} -> atn
      {:error, reason} -> raise ArgumentError, "invalid serialized ATN: #{inspect(reason)}"
    end
  end

  defp decode(cursor) do
    cursor =
      cursor
      |> read_header()
      |> read_states()
      |> read_rules()
      |> read_modes()
      |> read_sets()
      |> read_edges()
      |> add_rule_stop_edges()
      |> link_states()
      |> read_decisions()
      |> read_lexer_actions()
      |> mark_precedence_decisions()

    if cursor.p == cursor.size do
      {:ok, build_atn(cursor)}
    else
      {:error, {:unconsumed, cursor.p, cursor.size}}
    end
  end

  # --- Header -------------------------------------------------------------

  defp read_header(cursor) do
    {grammar_type, cursor} = read1(cursor)
    {max_token_type, cursor} = read1(cursor)
    %{cursor | grammar_type: grammar_type(grammar_type), max_token_type: max_token_type}
  end

  defp grammar_type(0), do: :lexer
  defp grammar_type(1), do: :parser

  # --- States -------------------------------------------------------------

  defp read_states(cursor) do
    {nstates, cursor} = read1(cursor)
    cursor = reduce_range(nstates, %{cursor | num_states: nstates}, &read_state/2)

    {non_greedy, cursor} = read1(cursor)
    cursor = reduce_range(non_greedy, cursor, &mark_non_greedy/2)

    {precedence, cursor} = read1(cursor)
    reduce_range(precedence, cursor, &mark_precedence_rule/2)
  end

  defp read_state(index, cursor) do
    {stype_id, cursor} = read1(cursor)

    case State.type_from_id(stype_id) do
      :invalid ->
        put_state(cursor, index, nil)

      type ->
        {rule_index, cursor} = read1(cursor)
        state = %State{state_number: index, state_type: type, rule_index: rule_index}
        {state, cursor} = read_state_extra(state, type, cursor)
        put_state(cursor, index, state)
    end
  end

  defp read_state_extra(state, :loop_end, cursor) do
    {loop_back, cursor} = read1(cursor)
    {%{state | loop_back_state: loop_back}, cursor}
  end

  defp read_state_extra(state, type, cursor) do
    if State.block_start?(type) do
      {end_state, cursor} = read1(cursor)
      {%{state | end_state: end_state}, cursor}
    else
      {state, cursor}
    end
  end

  defp mark_non_greedy(_index, cursor) do
    {state_number, cursor} = read1(cursor)
    update_state(cursor, state_number, &%{&1 | non_greedy: true})
  end

  defp mark_precedence_rule(_index, cursor) do
    {state_number, cursor} = read1(cursor)
    update_state(cursor, state_number, &%{&1 | is_precedence_rule: true})
  end

  # --- Rules --------------------------------------------------------------

  defp read_rules(cursor) do
    {nrules, cursor} = read1(cursor)
    lexer? = cursor.grammar_type == :lexer

    {starts, token_types, cursor} =
      reduce_range(nrules, {[], [], cursor}, fn _index, {starts, token_types, cursor} ->
        {start, cursor} = read1(cursor)

        if lexer? do
          {token_type, cursor} = read1(cursor)
          {[start | starts], [token_type | token_types], cursor}
        else
          {[start | starts], token_types, cursor}
        end
      end)

    cursor = %{
      cursor
      | rule_to_start_state: Enum.reverse(starts),
        rule_to_token_type: if(lexer?, do: Enum.reverse(token_types), else: nil)
    }

    link_rule_stops(cursor)
  end

  defp link_rule_stops(cursor) do
    stop_by_rule =
      cursor.states
      |> Map.values()
      |> Enum.reduce(%{}, fn
        %State{state_type: :rule_stop} = state, acc ->
          Map.put(acc, state.rule_index, state.state_number)

        _state, acc ->
          acc
      end)

    rule_to_stop_state = Enum.map(cursor.rule_to_start_state, fn _ -> nil end)

    rule_to_stop_state =
      cursor.rule_to_start_state
      |> Enum.with_index()
      |> Enum.reduce(rule_to_stop_state, fn {_start, rule_index}, acc ->
        List.replace_at(acc, rule_index, Map.fetch!(stop_by_rule, rule_index))
      end)

    cursor = %{cursor | rule_to_stop_state: rule_to_stop_state}

    cursor.rule_to_start_state
    |> Enum.zip(rule_to_stop_state)
    |> Enum.reduce(cursor, fn {start, stop}, cursor ->
      update_state(cursor, start, &%{&1 | stop_state: stop})
    end)
  end

  # --- Modes --------------------------------------------------------------

  defp read_modes(cursor) do
    {nmodes, cursor} = read1(cursor)

    {modes, cursor} =
      reduce_range(nmodes, {[], cursor}, fn _index, {modes, cursor} ->
        {state_number, cursor} = read1(cursor)
        {[state_number | modes], cursor}
      end)

    %{cursor | mode_to_start_state: Enum.reverse(modes)}
  end

  # --- Interval sets ------------------------------------------------------

  defp read_sets(cursor) do
    {nsets, cursor} = read1(cursor)

    {sets, cursor} =
      reduce_range(nsets, {[], cursor}, fn _index, {sets, cursor} ->
        {set, cursor} = read_set(cursor)
        {[set | sets], cursor}
      end)

    %{cursor | sets: Enum.reverse(sets)}
  end

  defp read_set(cursor) do
    {nintervals, cursor} = read1(cursor)
    {contains_eof, cursor} = read1(cursor)

    set =
      if contains_eof != 0,
        do: IntervalSet.add_one(IntervalSet.new(), @eof),
        else: IntervalSet.new()

    reduce_range(nintervals, {set, cursor}, fn _index, {set, cursor} ->
      {low, cursor} = read1(cursor)
      {high, cursor} = read1(cursor)
      {IntervalSet.add_range(set, low, high), cursor}
    end)
  end

  # --- Edges --------------------------------------------------------------

  defp read_edges(cursor) do
    {nedges, cursor} = read1(cursor)
    reduce_range(nedges, cursor, &read_edge/2)
  end

  defp read_edge(_index, cursor) do
    {src, cursor} = read1(cursor)
    {trg, cursor} = read1(cursor)
    {ttype, cursor} = read1(cursor)
    {arg1, cursor} = read1(cursor)
    {arg2, cursor} = read1(cursor)
    {arg3, cursor} = read1(cursor)

    transition = edge_factory(ttype, trg, arg1, arg2, arg3, cursor.sets)
    update_state(cursor, src, &State.add_transition(&1, transition))
  end

  defp edge_factory(1, trg, _a1, _a2, _a3, _sets),
    do: %Transition{type: :epsilon, target: trg}

  defp edge_factory(2, trg, a1, a2, 0, _sets),
    do: %Transition{type: :range, target: trg, from: a1, to: a2}

  defp edge_factory(2, trg, _a1, a2, _a3, _sets),
    do: %Transition{type: :range, target: trg, from: @eof, to: a2}

  defp edge_factory(3, trg, a1, a2, a3, _sets) do
    %Transition{
      type: :rule,
      target: a1,
      rule_start: a1,
      rule_index: a2,
      precedence: a3,
      follow_state: trg
    }
  end

  defp edge_factory(4, trg, a1, a2, a3, _sets),
    do: %Transition{
      type: :predicate,
      target: trg,
      rule_index: a1,
      pred_index: a2,
      ctx_dependent: a3 != 0
    }

  defp edge_factory(5, trg, a1, _a2, 0, _sets),
    do: %Transition{type: :atom, target: trg, label: a1}

  defp edge_factory(5, trg, _a1, _a2, _a3, _sets),
    do: %Transition{type: :atom, target: trg, label: @eof}

  defp edge_factory(6, trg, a1, a2, a3, _sets),
    do: %Transition{
      type: :action,
      target: trg,
      rule_index: a1,
      action_index: a2,
      ctx_dependent: a3 != 0
    }

  defp edge_factory(7, trg, a1, _a2, _a3, sets),
    do: %Transition{type: :set, target: trg, set: Enum.at(sets, a1)}

  defp edge_factory(8, trg, a1, _a2, _a3, sets),
    do: %Transition{type: :not_set, target: trg, set: Enum.at(sets, a1)}

  defp edge_factory(9, trg, _a1, _a2, _a3, _sets),
    do: %Transition{type: :wildcard, target: trg}

  defp edge_factory(10, trg, a1, _a2, _a3, _sets),
    do: %Transition{type: :precedence, target: trg, precedence: a1}

  # --- Derived rule-stop return edges ------------------------------------

  defp add_rule_stop_edges(cursor) do
    rule_transitions =
      cursor.states
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(fn %State{transitions: transitions} ->
        Enum.filter(transitions, &(&1.type == :rule))
      end)

    Enum.reduce(rule_transitions, cursor, &add_rule_stop_edge/2)
  end

  defp add_rule_stop_edge(%Transition{} = rule_transition, cursor) do
    called_rule = Map.fetch!(cursor.states, rule_transition.rule_start).rule_index
    stop_state = Enum.at(cursor.rule_to_stop_state, called_rule)

    epsilon = %Transition{
      type: :epsilon,
      target: rule_transition.follow_state,
      outermost_precedence_return:
        outermost_precedence_return(cursor, rule_transition, called_rule)
    }

    update_state(cursor, stop_state, &State.add_transition(&1, epsilon))
  end

  defp outermost_precedence_return(cursor, %Transition{precedence: precedence}, called_rule) do
    start_state = Enum.at(cursor.rule_to_start_state, called_rule)
    precedence_rule? = Map.fetch!(cursor.states, start_state).is_precedence_rule

    if precedence_rule? and precedence == 0, do: called_rule, else: @eof
  end

  # --- Block, loop, and rule linkage -------------------------------------

  defp link_states(cursor) do
    cursor.states
    |> Map.values()
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(cursor, &link_state/2)
  end

  defp link_state(%State{state_type: type} = state, cursor) do
    cond do
      State.block_start?(type) ->
        update_state(cursor, state.end_state, &%{&1 | start_state: state.state_number})

      type == :plus_loop_back ->
        link_loop_back(cursor, state, :plus_block_start)

      type == :star_loop_back ->
        link_loop_back(cursor, state, :star_loop_entry)

      true ->
        cursor
    end
  end

  defp link_loop_back(cursor, %State{} = loop_back, target_type) do
    Enum.reduce(loop_back.transitions, cursor, fn %Transition{target: target}, cursor ->
      case Map.get(cursor.states, target) do
        %State{state_type: ^target_type} ->
          update_state(cursor, target, &%{&1 | loop_back_state: loop_back.state_number})

        _other ->
          cursor
      end
    end)
  end

  # --- Decisions ----------------------------------------------------------

  defp read_decisions(cursor) do
    {ndecisions, cursor} = read1(cursor)

    {decisions, cursor} =
      reduce_range(ndecisions, {[], cursor}, fn index, {decisions, cursor} ->
        {state_number, cursor} = read1(cursor)
        cursor = update_state(cursor, state_number, &%{&1 | decision: index})
        {[state_number | decisions], cursor}
      end)

    %{cursor | decision_to_state: Enum.reverse(decisions)}
  end

  # --- Lexer actions ------------------------------------------------------

  defp read_lexer_actions(%{grammar_type: :parser} = cursor), do: cursor

  defp read_lexer_actions(%{grammar_type: :lexer} = cursor) do
    {count, cursor} = read1(cursor)

    {actions, cursor} =
      reduce_range(count, {[], cursor}, fn _index, {actions, cursor} ->
        {ordinal, cursor} = read1(cursor)
        {data1, cursor} = read1(cursor)
        {data2, cursor} = read1(cursor)
        {[LexerAction.from_serialized(ordinal, data1, data2) | actions], cursor}
      end)

    %{cursor | lexer_actions: Enum.reverse(actions)}
  end

  # --- Precedence decisions ----------------------------------------------

  defp mark_precedence_decisions(cursor) do
    cursor.states
    |> Map.values()
    |> Enum.reduce(cursor, fn
      %State{state_type: :star_loop_entry} = state, cursor ->
        mark_precedence_decision(cursor, state)

      _state, cursor ->
        cursor
    end)
  end

  defp mark_precedence_decision(cursor, %State{} = entry) do
    rule_start = Enum.at(cursor.rule_to_start_state, entry.rule_index)
    precedence_rule? = Map.fetch!(cursor.states, rule_start).is_precedence_rule

    if precedence_rule? and precedence_loop?(cursor, entry) do
      update_state(cursor, entry.state_number, &%{&1 | is_precedence_decision: true})
    else
      cursor
    end
  end

  defp precedence_loop?(cursor, %State{transitions: transitions}) do
    with %Transition{target: target} <- List.last(transitions),
         %State{state_type: :loop_end} = loop_end <- Map.get(cursor.states, target),
         true <- Enum.all?(loop_end.transitions, &Transition.epsilon?/1),
         %Transition{target: first_target} <- List.first(loop_end.transitions),
         %State{state_type: :rule_stop} <- Map.get(cursor.states, first_target) do
      true
    else
      _other -> false
    end
  end

  # --- Assembly -----------------------------------------------------------

  defp build_atn(cursor) do
    %ATN{
      grammar_type: cursor.grammar_type,
      max_token_type: cursor.max_token_type,
      states: cursor.states,
      num_states: cursor.num_states,
      rule_to_start_state: cursor.rule_to_start_state,
      rule_to_stop_state: cursor.rule_to_stop_state,
      rule_to_token_type: cursor.rule_to_token_type,
      mode_to_start_state: cursor.mode_to_start_state,
      decision_to_state: cursor.decision_to_state,
      lexer_actions: cursor.lexer_actions,
      sets: cursor.sets,
      cache_key: cursor.cache_key
    }
  end

  # --- Cursor helpers -----------------------------------------------------

  defp read1(%{data: data, p: p} = cursor), do: {elem(data, p), %{cursor | p: p + 1}}

  defp put_state(cursor, number, state),
    do: %{cursor | states: Map.put(cursor.states, number, state)}

  defp update_state(cursor, number, fun),
    do: %{cursor | states: Map.update!(cursor.states, number, fun)}

  # Runs `fun` for indices 0..count-1, threading the accumulator. `count`
  # may be zero, in which case the accumulator is returned unchanged.
  defp reduce_range(0, acc, _fun), do: acc
  defp reduce_range(count, acc, fun), do: Enum.reduce(0..(count - 1), acc, fun)
end
