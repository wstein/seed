defmodule Seed.ParserATNSimulator do
  @moduledoc """
  Predicts which alternative a parser decision should take by simulating the
  ATN over the upcoming tokens (adaptive LL(*)).

  Prediction uses the parser's **full** rule-invocation context: the start
  state is built from the real call stack (`from_rule_context`), so
  context-sensitive decisions — where the viable alternative depends on who
  called the rule — are resolved correctly. It therefore does not need the
  reference's separate SLL-first stage, which trades that context away for
  cacheability; adding that optimization is future work.

  Without that SLL fast path, full-context prediction can explode on a highly
  ambiguous grammar (a single decision exploring an unbounded
  configuration/context space). A closure that exceeds its step,
  configuration, recursion-depth, or heap bound therefore fails *gracefully*
  with a `:prediction_overflow` diagnostic rather than exhausting memory or
  burning CPU — the parse returns `{:error, …}` instead of taking down the VM.

  From the decision's start state it computes the epsilon-closure, then
  advances the configuration set token by token (over a private lookahead
  copy of the input) until one alternative survives or the survivors are in
  irreducible conflict, in which case the lowest alternative wins (ANTLR's
  default ambiguity resolution). Left-recursive decisions are handled by the
  precedence filter, which uses the parser's current precedence to drop
  lower-priority alternatives. Results are memoized in `Seed.DFACache`.
  """

  alias Seed.ATN.ATNConfig
  alias Seed.ATN.ParserATNConfigSet
  alias Seed.ATN.PredictionContext
  alias Seed.ATN.PredictionMode
  alias Seed.ATN.SemanticContext
  alias Seed.ATN.SemanticContext.PrecedencePredicate
  alias Seed.ATN.State
  alias Seed.ATN.Transition
  alias Seed.DFACache
  alias Seed.Diagnostic
  alias Seed.Parser
  alias Seed.TokenStream

  # Bounds a single decision's closure so full-context prediction cannot
  # exhaust memory or burn CPU on an ambiguous grammar (Seed has no SLL fast
  # path to bound it). Real grammars stay far below these even on complex
  # decisions, so exceeding any of them means prediction is exploding, and it
  # fails gracefully with a diagnostic. The heap-size guard is the catch-all:
  # the explosion can hide in a few configurations carrying gigantic merged
  # prediction contexts, which a count- or depth-based limit alone misses.
  @max_recursion_depth 2_000
  @max_closure_configs 50_000
  # Total closure steps a single decision may take. Real decisions take at
  # most tens of thousands; this catches an explosion in well under a second
  # (by work done, not memory consumed — the giant merged context that hides
  # the blow-up shows up as steps before it shows up as configurations).
  @max_closure_steps 200_000
  # ~128 MB of process heap (words) — the catch-all for an explosion that is
  # memory-heavy but neither step- nor configuration-heavy (a few giant merged
  # contexts). Well under the 2 GB VM cap.
  @max_closure_heap_words 16_000_000

  @doc """
  Returns the 1-based alternative to take at `decision` given the parser's
  current position and rule context.
  """
  @spec adaptive_predict(Parser.t(), non_neg_integer()) :: pos_integer()
  def adaptive_predict(%Parser{atn: atn} = parser, decision) do
    Process.put(:seed_closure_steps, 0)
    decision_state = Map.fetch!(atn.states, Enum.at(atn.decision_to_state, decision))
    outer_context = from_rule_context(atn, parser.frames)

    # The start-state closure and reach are pure functions of the grammar,
    # decision/configs, and lookahead — not the parser — so they are cached
    # by those alone. The precedence filter (below) does depend on the
    # parser's precedence, so it stays outside the cache.
    start =
      DFACache.memoize({atn.cache_key, :parser_start, decision, outer_context}, fn ->
        compute_start_state(atn, decision_state, outer_context, parser)
      end)

    start =
      if decision_state.state_type == :star_loop_entry and decision_state.is_precedence_decision do
        apply_precedence_filter(start, parser)
      else
        start
      end

    decide(atn, start, parser.input, parser)
  end

  # Builds the prediction context for the call stack above the decision.
  defp from_rule_context(_atn, []), do: :empty
  defp from_rule_context(_atn, [%{invoking_state: -1} | _]), do: :empty

  defp from_rule_context(atn, [frame | rest]) do
    parent = from_rule_context(atn, rest)
    follow = hd(Map.fetch!(atn.states, frame.invoking_state).transitions).follow_state
    PredictionContext.singleton(parent, follow)
  end

  # --- Start state and precedence filter ----------------------------------

  defp compute_start_state(atn, state, context, parser) do
    state.transitions
    |> Enum.with_index()
    |> Enum.reduce(ParserATNConfigSet.new(true), fn {transition, index}, configs ->
      config = %ATNConfig{state: transition.target, alt: index + 1, context: context}
      {configs, _busy} = closure(atn, config, {configs, MapSet.new()}, true, parser)
      configs
    end)
  end

  defp apply_precedence_filter(config_set, parser) do
    precpred = precedence_evaluator(parser)
    configs = ParserATNConfigSet.configs(config_set)
    {filtered, states_from_alt1} = keep_primary_alts(configs, precpred)
    keep_higher_alts(configs, filtered, states_from_alt1)
  end

  defp keep_primary_alts(configs, precpred) do
    Enum.reduce(configs, {ParserATNConfigSet.new(true), %{}}, fn
      %ATNConfig{alt: 1} = config, {set, states} ->
        case SemanticContext.eval_precedence(config.semantic_context, precpred) do
          nil ->
            {set, states}

          updated ->
            {ParserATNConfigSet.add(set, %{config | semantic_context: updated}),
             Map.put(states, config.state, config.context)}
        end

      _config, acc ->
        acc
    end)
  end

  defp keep_higher_alts(configs, filtered, states_from_alt1) do
    Enum.reduce(configs, filtered, fn
      %ATNConfig{alt: 1}, set ->
        set

      config, set ->
        if not config.precedence_filter_suppressed and
             Map.get(states_from_alt1, config.state) == config.context do
          set
        else
          ParserATNConfigSet.add(set, config)
        end
    end)
  end

  defp precedence_evaluator(parser) do
    current = Parser.precedence(parser)

    fn
      %PrecedencePredicate{precedence: precedence} -> precedence >= current
      _other -> true
    end
  end

  # --- Prediction loop ----------------------------------------------------

  defp decide(atn, configs, input, parser) do
    t = TokenStream.la(input, 1)
    reach = cached_reach_set(atn, configs, t, parser)

    if ParserATNConfigSet.empty?(reach) do
      predict_from(atn, configs, input, parser)
    else
      resolve(atn, reach, input, parser)
    end
  end

  # Memoizes each edge: the reach for a configuration set on a token type
  # depends only on the grammar, the set, and the token.
  defp cached_reach_set(atn, configs, t, parser) do
    DFACache.memoize({atn.cache_key, :parser_edge, ParserATNConfigSet.configs(configs), t}, fn ->
      compute_reach_set(atn, configs, t, parser)
    end)
  end

  defp resolve(atn, reach, input, parser) do
    reach_configs = ParserATNConfigSet.configs(reach)
    unique = PredictionMode.unique_alt(reach_configs)

    cond do
      unique != 0 -> unique
      PredictionMode.conflict?(reach, atn) -> resolve_conflict(reach_configs, parser)
      true -> decide(atn, reach, TokenStream.consume(input), parser)
    end
  end

  # Conflicting alternatives: if any carries a semantic predicate, evaluate
  # the predicates and take the lowest alternative whose predicate holds;
  # otherwise it is a pure syntactic ambiguity, resolved (as ANTLR does) to
  # the lowest alternative. If every predicate fails, fall back to the lowest
  # alternative rather than manufacturing a no-viable error.
  defp resolve_conflict(reach_configs, parser) do
    case predicated_alts(reach_configs) do
      [] -> PredictionMode.min_alt(reach_configs)
      alt_predicates -> lowest_satisfied_alt(alt_predicates, reach_configs, parser)
    end
  end

  defp lowest_satisfied_alt(alt_predicates, reach_configs, parser) do
    evaluator = leaf_evaluator(parser)

    case for {alt, ctx} <- alt_predicates, SemanticContext.eval(ctx, evaluator), do: alt do
      [] -> PredictionMode.min_alt(reach_configs)
      satisfied -> Enum.min(satisfied)
    end
  end

  # Maps each alternative to the disjunction of its configurations' semantic
  # contexts (an alternative reachable by any predicate-free path is
  # unconditionally satisfied, since `or_op` absorbs `:none`). Returns `[]`
  # when no alternative is predicated — the common, no-predicate case.
  defp predicated_alts(configs) do
    by_alt =
      Enum.reduce(configs, %{}, fn config, acc ->
        Map.update(acc, config.alt, config.semantic_context, fn existing ->
          SemanticContext.or_op(existing, config.semantic_context)
        end)
      end)

    if Enum.all?(by_alt, fn {_alt, ctx} -> ctx == :none end) do
      []
    else
      Map.to_list(by_alt)
    end
  end

  # A leaf evaluator for `SemanticContext.eval/2`: grammar predicates defer to
  # the parser's `sempred` callback (with the current rule context), and
  # precedence predicates compare against the parser's current precedence.
  defp leaf_evaluator(parser) do
    context = Parser.current_context(parser)
    current_precedence = Parser.precedence(parser)

    fn
      %SemanticContext.Predicate{rule_index: rule_index, pred_index: pred_index} ->
        parser.sempred.(rule_index, pred_index, context)

      %PrecedencePredicate{precedence: precedence} ->
        precedence >= current_precedence
    end
  end

  # No alternative can consume the next token. Prefer an alternative that has
  # reached the decision's rule-stop state — it accepts here without consuming
  # (the lowest such, ANTLR's ambiguity convention); this is what lets a
  # decision exit under an empty outer context, e.g. the precedence loop of a
  # left-recursive rule parsed as the start rule. With no accepting
  # alternative the input is genuinely unparseable at this decision, so report
  # a no-viable-alternative — bailing in `:bail` mode, otherwise throwing the
  # parser back to the interpreter for panic-mode resynchronization (the same
  # channel as a match failure).
  defp predict_from(atn, configs, input, parser) do
    case stop_state_alts(atn, ParserATNConfigSet.configs(configs)) do
      [] -> fail_prediction(parser, no_viable_alternative(input))
      alts -> Enum.min(alts)
    end
  end

  @spec fail_prediction(Parser.t(), Diagnostic.t()) :: no_return()
  defp fail_prediction(%Parser{error_mode: :bail}, diagnostic) do
    throw({:seed_bail, diagnostic})
  end

  defp fail_prediction(parser, diagnostic) do
    throw({:seed_resync, Parser.add_diagnostic(parser, diagnostic)})
  end

  defp stop_state_alts(atn, configs) do
    for config <- configs,
        Map.fetch!(atn.states, config.state).state_type == :rule_stop,
        do: config.alt
  end

  defp no_viable_alternative(input) do
    token = TokenStream.lt(input, 1)

    Diagnostic.error(:no_viable_alternative, "no viable alternative at input",
      line: token.line,
      column: token.column
    )
  end

  # --- Reach --------------------------------------------------------------

  defp compute_reach_set(atn, configs, t, parser) do
    intermediate = reachable_configs(atn, ParserATNConfigSet.configs(configs), t)

    {reach, _busy} =
      Enum.reduce(intermediate, {ParserATNConfigSet.new(true), MapSet.new()}, fn config, acc ->
        closure(atn, config, acc, false, parser)
      end)

    reach
  end

  defp reachable_configs(atn, configs, t) do
    Enum.flat_map(configs, &reachable_from(atn, &1, t))
  end

  defp reachable_from(atn, config, t) do
    case Map.fetch!(atn.states, config.state) do
      %State{state_type: :rule_stop} ->
        []

      state ->
        for transition <- state.transitions,
            matches?(transition, t),
            do: %{config | state: transition.target}
    end
  end

  # --- Closure ------------------------------------------------------------

  defp closure(atn, config, acc, collect, parser) do
    closure_checking_stop_state(atn, config, acc, collect, 0, parser)
  end

  defp closure_checking_stop_state(atn, config, {configs, busy}, collect, depth, parser) do
    if count_step() or ParserATNConfigSet.size(configs) >= @max_closure_configs or over_heap?(),
      do: prediction_overflow(parser)

    case Map.fetch!(atn.states, config.state) do
      %State{state_type: :rule_stop} ->
        closure_at_stop(atn, config, {configs, busy}, collect, depth, parser)

      state ->
        closure_step(atn, config, state, {configs, busy}, collect, depth, parser)
    end
  end

  defp closure_at_stop(atn, config, {configs, busy}, collect, depth, parser) do
    if PredictionContext.empty?(config.context) do
      {ParserATNConfigSet.add(configs, config), busy}
    else
      pop_context(atn, config, {configs, busy}, collect, depth, parser)
    end
  end

  defp pop_context(atn, config, acc, collect, depth, parser) do
    Enum.reduce(0..(PredictionContext.size(config.context) - 1), acc, fn index, {configs, busy} ->
      return_state = PredictionContext.return_state(config.context, index)

      if return_state == PredictionContext.empty_return_state() do
        {ParserATNConfigSet.add(configs, %{config | context: :empty}), busy}
      else
        popped = %{
          config
          | state: return_state,
            context: PredictionContext.parent(config.context, index)
        }

        closure_checking_stop_state(atn, popped, {configs, busy}, collect, depth - 1, parser)
      end
    end)
  end

  defp closure_step(atn, config, state, {configs, busy}, collect, depth, parser) do
    configs =
      if has_non_epsilon?(state), do: ParserATNConfigSet.add(configs, config), else: configs

    Enum.reduce(state.transitions, {configs, busy}, fn transition, acc ->
      follow_epsilon(atn, config, transition, acc, collect, depth, parser)
    end)
  end

  defp follow_epsilon(atn, config, transition, {configs, busy}, collect, depth, parser) do
    case epsilon_target(config, transition, collect, depth == 0) do
      nil -> {configs, busy}
      target -> visit_target(atn, target, transition, {configs, busy}, collect, depth, parser)
    end
  end

  defp visit_target(atn, target, transition, {configs, busy}, collect, depth, parser) do
    if MapSet.member?(busy, target) do
      {configs, busy}
    else
      descend(atn, target, transition, {configs, busy}, collect, depth, parser)
    end
  end

  defp descend(atn, target, transition, {configs, busy}, collect, depth, parser) do
    new_depth = if transition.type == :rule, do: depth + 1, else: depth

    if new_depth > @max_recursion_depth, do: prediction_overflow(parser)

    closure_checking_stop_state(
      atn,
      target,
      {configs, MapSet.put(busy, target)},
      collect,
      new_depth,
      parser
    )
  end

  # Counts one closure step against this decision's budget (reset per
  # `adaptive_predict`); returns `true` once the budget is exceeded.
  defp count_step do
    steps = Process.get(:seed_closure_steps, 0) + 1
    Process.put(:seed_closure_steps, steps)
    steps > @max_closure_steps
  end

  defp over_heap? do
    {:total_heap_size, words} = :erlang.process_info(self(), :total_heap_size)
    words > @max_closure_heap_words
  end

  @spec prediction_overflow(Parser.t()) :: no_return()
  defp prediction_overflow(parser) do
    token = TokenStream.lt(parser.input, 1)

    diagnostic =
      Diagnostic.error(
        :prediction_overflow,
        "prediction exceeded the configuration bound; the grammar is too ambiguous " <>
          "for full-context prediction at this point",
        line: token.line,
        column: token.column
      )

    throw({:seed_overflow, diagnostic})
  end

  defp epsilon_target(config, %Transition{type: :rule} = transition, _collect, _in_context) do
    context = PredictionContext.singleton(config.context, transition.follow_state)
    %{config | state: transition.target, context: context}
  end

  defp epsilon_target(config, %Transition{type: :precedence} = transition, collect, in_context) do
    if collect and in_context do
      pred = %PrecedencePredicate{precedence: transition.precedence}

      %{
        config
        | state: transition.target,
          semantic_context: SemanticContext.and_op(config.semantic_context, pred)
      }
    else
      %{config | state: transition.target}
    end
  end

  defp epsilon_target(config, %Transition{type: :predicate} = transition, collect, in_context) do
    if collect and in_context do
      pred = %SemanticContext.Predicate{
        rule_index: transition.rule_index,
        pred_index: transition.pred_index,
        ctx_dependent: transition.ctx_dependent
      }

      %{
        config
        | state: transition.target,
          semantic_context: SemanticContext.and_op(config.semantic_context, pred)
      }
    else
      %{config | state: transition.target}
    end
  end

  defp epsilon_target(config, %Transition{type: type} = transition, _collect, _in_context)
       when type in [:action, :epsilon] do
    %{config | state: transition.target}
  end

  defp epsilon_target(_config, %Transition{}, _collect, _in_context), do: nil

  # --- Symbol matching ----------------------------------------------------

  defp matches?(transition, t), do: Transition.matches?(transition, t)

  defp has_non_epsilon?(%State{transitions: transitions}) do
    Enum.any?(transitions, &(not Transition.epsilon?(&1)))
  end
end
