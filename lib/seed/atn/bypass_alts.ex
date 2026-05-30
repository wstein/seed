defmodule Seed.ATN.BypassAlts do
  @moduledoc """
  Adds *rule-bypass alternatives* to a parser ATN, after the reference
  `ATNDeserializer.generateRuleBypassTransitions` (`getATNWithBypassAlts()`).

  The tree-pattern matcher (`Seed.TreePatternMatcher`) compiles a pattern like
  `<expr> + <expr>` by parsing it with the grammar that produced the subject
  tree. A `<rule>` tag must be matchable as a single token, which the ordinary
  ATN cannot do. This transform gives every rule an imaginary token type
  (`max_token_type + rule_index + 1`) and an extra alternative — a block whose
  bypass arm matches exactly that one token — so parsing `<expr>` yields an
  `expr` context whose only child is the tag terminal.

  The transform is structural and pure: it returns a new `Seed.ATN` and is
  only meaningful for parser grammars. It is *not* applied to the runtime ATN
  used for ordinary parsing — only when compiling a tree pattern.
  """

  alias Seed.ATN
  alias Seed.ATN.State
  alias Seed.ATN.Transition

  @doc """
  Returns `atn` with rule-bypass transitions added.

  Assigns `rule_to_token_type` (the imaginary per-rule token types) and, for
  each rule, inserts the bypass block. Raises for a lexer ATN.
  """
  @spec add(ATN.t()) :: ATN.t()
  def add(%ATN{grammar_type: :parser} = atn) do
    nrules = length(atn.rule_to_start_state)
    token_types = Enum.map(0..(nrules - 1), &(atn.max_token_type + &1 + 1))

    # The bypass ATN is a *different* graph (extra states, decisions, and
    # rule-start rewiring), but `Seed.DFACache` keys parser start states by
    # `{cache_key, :parser_start, decision, …}` without the config set — so
    # sharing the source ATN's `cache_key` would let a pattern compile poison
    # the entries normal parsing reads (and vice versa). Give it its own key.
    atn = %{atn | rule_to_token_type: token_types, cache_key: bypass_cache_key(atn.cache_key)}

    Enum.reduce(0..(nrules - 1), atn, &add_rule_bypass/2)
  end

  def add(%ATN{grammar_type: :lexer}) do
    raise ArgumentError, "rule-bypass transitions apply only to parser ATNs"
  end

  defp bypass_cache_key(cache_key), do: :erlang.phash2({cache_key, :bypass})

  defp add_rule_bypass(rule_index, atn) do
    base = atn.num_states
    bypass_start_no = base
    bypass_stop_no = base + 1
    match_no = base + 2

    decision = length(atn.decision_to_state)
    token_type = Enum.at(atn.rule_to_token_type, rule_index)

    rule_start_no = Enum.at(atn.rule_to_start_state, rule_index)
    rule_start = Map.fetch!(atn.states, rule_start_no)
    {end_no, exclude} = wrap_target(atn, rule_index, rule_start)

    # 1. Every non-excluded transition that targets the rule's end state must
    #    now target the bypass block's end instead.
    states = redirect(atn.states, end_no, bypass_stop_no, exclude)

    # 2. The rule-start's transitions become the bypass block's first
    #    alternative; the rule start keeps only an epsilon into the block.
    moved = Map.fetch!(states, rule_start_no).transitions
    rule_start = %{rule_start | transitions: []}
    rule_start = State.add_transition(rule_start, epsilon(bypass_start_no))

    bypass_start =
      %State{
        state_number: bypass_start_no,
        state_type: :block_start,
        rule_index: rule_index,
        decision: decision,
        end_state: bypass_stop_no
      }

    # The reference moves them by repeatedly removing the *last* transition, so
    # they land on `bypassStart` reversed; match that for faithfulness. (A rule
    # start has a single transition in practice, so the order is moot, but
    # mirroring the reference avoids a latent divergence on any multi-transition
    # start state.)
    bypass_start = Enum.reduce(Enum.reverse(moved), bypass_start, &State.add_transition(&2, &1))

    # 3. The bypass arm: match the imaginary token, then rejoin the rule's flow.
    match_state =
      %State{state_number: match_no, state_type: :basic, rule_index: rule_index}
      |> State.add_transition(%Transition{type: :atom, target: bypass_stop_no, label: token_type})

    bypass_start = State.add_transition(bypass_start, epsilon(match_no))

    bypass_stop =
      %State{
        state_number: bypass_stop_no,
        state_type: :block_end,
        rule_index: rule_index,
        start_state: bypass_start_no
      }
      |> State.add_transition(epsilon(end_no))

    states =
      states
      |> Map.put(rule_start_no, rule_start)
      |> Map.put(bypass_start_no, bypass_start)
      |> Map.put(bypass_stop_no, bypass_stop)
      |> Map.put(match_no, match_state)

    %{
      atn
      | states: states,
        num_states: base + 3,
        decision_to_state: atn.decision_to_state ++ [bypass_start_no]
    }
  end

  # A plain rule wraps the whole rule (start..stop). A left-recursive
  # (precedence) rule wraps only the prefix section, ending at the
  # `StarLoopEntry`, and excludes the loop-back edge so the recursion still
  # loops rather than bypassing out.
  defp wrap_target(_atn, _rule_index, %State{is_precedence_rule: false} = rule_start) do
    {rule_start.stop_state, nil}
  end

  defp wrap_target(atn, rule_index, %State{is_precedence_rule: true}) do
    entry = precedence_loop_entry(atn, rule_index)
    loop_back_no = entry.loop_back_state
    {entry.state_number, {loop_back_no, 0}}
  end

  defp precedence_loop_entry(atn, rule_index) do
    atn.states
    |> Map.values()
    |> Enum.find(fn state ->
      match?(%State{state_type: :star_loop_entry, rule_index: ^rule_index}, state) and
        precedence_prefix_end?(atn, state)
    end)
    |> case do
      nil ->
        raise "couldn't identify final state of the precedence rule prefix section"

      entry ->
        entry
    end
  end

  # The `StarLoopEntry` that ends the prefix section is the one whose last
  # transition reaches a `LoopEnd` that epsilon-jumps straight to the rule stop.
  defp precedence_prefix_end?(_atn, %State{transitions: []}), do: false

  defp precedence_prefix_end?(atn, %State{} = state) do
    loop_end = Map.get(atn.states, List.last(state.transitions).target)

    with %State{state_type: :loop_end, transitions: [first | _] = ts} <- loop_end,
         true <- Enum.all?(ts, &Transition.epsilon?/1),
         %State{state_type: :rule_stop} <- Map.get(atn.states, first.target) do
      true
    else
      _ -> false
    end
  end

  defp redirect(states, end_no, bypass_stop_no, exclude) do
    Map.new(states, fn
      {num, nil} ->
        {num, nil}

      {num, %State{transitions: transitions} = state} ->
        redirected =
          transitions
          |> Enum.with_index()
          |> Enum.map(&redirect_one(&1, num, end_no, bypass_stop_no, exclude))

        {num, %{state | transitions: redirected}}
    end)
  end

  defp redirect_one({%Transition{target: target} = transition, index}, num, end_no, stop, exclude) do
    if target == end_no and not excluded?(exclude, num, index) do
      %{transition | target: stop}
    else
      transition
    end
  end

  defp excluded?(nil, _num, _index), do: false

  defp excluded?({loop_back_no, excluded_index}, num, index),
    do: num == loop_back_no and index == excluded_index

  defp epsilon(target), do: %Transition{type: :epsilon, target: target}
end
