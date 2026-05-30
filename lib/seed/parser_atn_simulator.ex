defmodule Seed.ParserATNSimulator do
  @moduledoc """
  Predicts which alternative a parser decision should take by simulating the
  ATN over the upcoming tokens (adaptive LL(*)).

  Prediction is two-stage, mirroring the reference. A decision first tries
  **SLL** (Strong-LL): the start state is built with an *empty* outer context,
  so its closure and DFA are shared across every call site and the context is
  not rebuilt from the call stack — the cacheable fast path. SLL is a sound
  over-approximation: a unique SLL result provably equals full-context LL's
  answer. Only a genuine SLL *conflict* — a consuming alternative coexisting
  with one that dipped into the unknown outer context (a config carried at its
  rule-stop, e.g. the empty alternative of `ctx_b`'s rule `e`) — retries in
  **full context**, where `from_rule_context` builds the start state from the
  real call stack and resolves the context-sensitive decision. Left-recursive
  (precedence) decisions predict in full context directly.

  Full-context prediction (the fallback) can still explode on a highly
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
  lower-priority alternatives.

  The walk is backed by a **persisted DFA** (`Seed.DFA`): each configuration
  set is interned to an integer id, the reach for `(state, token)` is recorded
  as an integer edge, and each state's resolution (accept / conflict /
  continue) is cached. After warm-up a step is two integer lookups rather than
  a config-set rehash and re-resolution, which is where most of the
  prediction-time speed comes from.
  """

  alias Seed.ATN.ATNConfig
  alias Seed.ATN.ParserATNConfigSet
  alias Seed.ATN.PredictionContext
  alias Seed.ATN.PredictionMode
  alias Seed.ATN.SemanticContext
  alias Seed.ATN.SemanticContext.PrecedencePredicate
  alias Seed.ATN.State
  alias Seed.ATN.Transition
  alias Seed.DFA
  alias Seed.DFACache
  alias Seed.Diagnostic
  alias Seed.Parser
  alias Seed.TokenStream

  # Bounds a single decision's closure so full-context prediction cannot
  # exhaust memory or burn CPU on an ambiguous grammar (the SLL fast path
  # handles the common case, but a genuine context-sensitive decision can still
  # fall through to an unbounded full-context closure). Real grammars stay far
  # below these even on complex
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

    # A precedence (left-recursive) decision predicts in full context directly —
    # its precedence-filtered start state is not SLL-shareable. Everything else
    # tries SLL first: an empty outer context, so the start state is shared
    # across every call site and the context need not be rebuilt from the frames.
    if precedence_decision?(decision_state) do
      ll_predict(atn, decision_state, parser, decision)
    else
      try_sll(atn, decision_state, parser, decision)
    end
  end

  defp precedence_decision?(%State{state_type: :star_loop_entry, is_precedence_decision: true}),
    do: true

  defp precedence_decision?(%State{}), do: false

  # SLL: predict with an empty outer context. A unique result is provably the
  # full-context answer (SLL soundness); only a genuine SLL *conflict* — a
  # consuming alternative coexisting with one that dipped into the unknown
  # outer context — retries in full context.
  defp try_sll(atn, decision_state, parser, decision) do
    {id, configs} = sll_start(atn, decision_state, decision, parser)
    decide(atn, {id, configs}, parser.input, parser, false)
  catch
    :sll_conflict ->
      # The SLL pass spent part of this decision's closure budget; give the LL
      # retry its own full budget so a complex full-context closure is not
      # starved into a spurious `:prediction_overflow`.
      Process.put(:seed_closure_steps, 0)
      ll_predict(atn, decision_state, parser, decision)
  end

  defp ll_predict(atn, decision_state, parser, decision) do
    outer_context = from_rule_context(atn, parser.frames)
    {id, configs} = ll_start(atn, decision_state, decision, outer_context, parser)
    decide(atn, {id, configs}, parser.input, parser, true)
  end

  # The SLL start state has an empty outer context and no precedence filter, so
  # its interned id and config list are shared across every call site —
  # memoized by decision alone.
  defp sll_start(atn, decision_state, decision, parser) do
    DFACache.memoize({atn.cache_key, :sll_start, decision}, fn ->
      atn
      |> compute_start_state(decision_state, :empty, parser, false)
      |> intern_start(atn)
    end)
  end

  # A non-precedence LL start depends only on the outer context, so it is
  # memoized; a precedence (left-recursive) start is filtered by the parser's
  # current precedence, so it is computed and interned fresh each time.
  defp ll_start(atn, decision_state, decision, outer_context, parser) do
    if precedence_decision?(decision_state) do
      atn
      |> compute_start_state(decision_state, outer_context, parser, true)
      |> apply_precedence_filter(parser)
      |> intern_start(atn)
    else
      DFACache.memoize({atn.cache_key, :ll_start, decision, outer_context}, fn ->
        atn
        |> compute_start_state(decision_state, outer_context, parser, true)
        |> intern_start(atn)
      end)
    end
  end

  defp intern_start(start_set, atn) do
    configs = ParserATNConfigSet.configs(start_set)
    {DFA.intern(atn.cache_key, configs), configs}
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

  defp compute_start_state(atn, state, context, parser, full_ctx?) do
    state.transitions
    |> Enum.with_index()
    |> Enum.reduce(ParserATNConfigSet.new(full_ctx?), fn {transition, index}, configs ->
      config = %ATNConfig{state: transition.target, alt: index + 1, context: context}
      {configs, _busy} = closure(atn, config, {configs, MapSet.new()}, true, parser, full_ctx?)
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

  # Walks the decision as a DFA: from the current state `id` (an interned
  # config set), the edge on the next token is a cached integer target, and the
  # target state's resolution (accept / conflict / continue) is cached too — so
  # a warm step is two integer lookups, not a config-set rehash and a
  # re-resolution. `configs` may be `nil` on a warm step (fetched only when an
  # edge or resolution misses).
  defp decide(atn, {id, configs}, input, parser, full_ctx?) do
    t = TokenStream.la(input, 1)

    case DFA.edge(atn.cache_key, id, t, full_ctx?) do
      nil -> compute_edge(atn, id, configs, t, input, parser, full_ctx?)
      :empty -> predict_from(atn, fetch(atn, id, configs), input, parser)
      target_id -> arrive(atn, target_id, input, parser, full_ctx?)
    end
  end

  # Edge miss: compute the reach, intern it, record the edge, and act on the
  # new state. An empty reach is recorded as `:empty` so the no-viable path is
  # cached too.
  defp compute_edge(atn, id, configs, t, input, parser, full_ctx?) do
    configs = fetch(atn, id, configs)

    case compute_reach_set(atn, configs, t, parser, full_ctx?) do
      [] ->
        DFA.put_edge(atn.cache_key, id, t, full_ctx?, :empty)
        predict_from(atn, configs, input, parser)

      reach ->
        target_id = DFA.intern(atn.cache_key, reach)
        DFA.put_edge(atn.cache_key, id, t, full_ctx?, target_id)

        act(
          atn,
          prediction!(atn, target_id, reach, full_ctx?),
          {target_id, reach},
          input,
          parser,
          full_ctx?
        )
    end
  end

  # Arrive at an interned state via a cached edge: take its cached resolution,
  # computing it (and fetching the configs) only on a miss.
  defp arrive(atn, id, input, parser, full_ctx?) do
    case DFA.prediction(atn.cache_key, id, full_ctx?) do
      {:accept, alt} -> alt
      :conflict -> on_conflict(DFA.configs(atn.cache_key, id), parser, full_ctx?)
      :continue -> decide(atn, {id, nil}, TokenStream.consume(input), parser, full_ctx?)
      nil -> resolve_state(atn, id, input, parser, full_ctx?)
    end
  end

  defp resolve_state(atn, id, input, parser, full_ctx?) do
    configs = DFA.configs(atn.cache_key, id)
    act(atn, prediction!(atn, id, configs, full_ctx?), {id, configs}, input, parser, full_ctx?)
  end

  defp act(atn, prediction, {id, configs}, input, parser, full_ctx?) do
    case prediction do
      {:accept, alt} -> alt
      :conflict -> on_conflict(configs, parser, full_ctx?)
      :continue -> decide(atn, {id, configs}, TokenStream.consume(input), parser, full_ctx?)
    end
  end

  # Computes and caches a state's resolution: a unique alternative accepts; an
  # irreducible conflict stops (to fall over to LL, or be resolved in LL);
  # otherwise prediction continues to the next token.
  defp prediction!(atn, id, configs, full_ctx?) do
    prediction =
      cond do
        (alt = PredictionMode.unique_alt(configs)) != 0 -> {:accept, alt}
        PredictionMode.conflict?(configs, atn) -> :conflict
        true -> :continue
      end

    DFA.put_prediction(atn.cache_key, id, full_ctx?, prediction)
    prediction
  end

  defp fetch(_atn, _id, configs) when is_list(configs), do: configs
  defp fetch(atn, id, nil), do: DFA.configs(atn.cache_key, id)

  # An SLL conflict may be a false ambiguity that the real outer context
  # resolves, so retry in full context; a full-context conflict is genuine
  # (resolved by predicate or the lowest alternative).
  #
  # The reference can short-circuit the SLL→LL retry when the conflicting
  # configurations carry predicates that already resolve to one alternative;
  # Seed always retries in full context, where the same predicates are
  # evaluated, so the result is identical and only a (rare) conflict pays the
  # extra LL pass.
  defp on_conflict(_reach_configs, _parser, false), do: throw(:sll_conflict)
  defp on_conflict(reach_configs, parser, true), do: resolve_conflict(reach_configs, parser)

  # Conflicting alternatives: if any carries a semantic predicate, evaluate
  # the predicates and take the lowest alternative whose predicate holds;
  # otherwise it is a pure syntactic ambiguity, resolved (as ANTLR does) to
  # the lowest alternative. If every predicate fails, fall back to the lowest
  # alternative rather than manufacturing a no-viable error.
  #
  # In full context the reference keeps scanning past a conflict until the
  # conflicting alternative subsets reduce to a single viable alternative
  # (`resolvesToJustOneViableAlt`), only then resolving. Seed resolves at the
  # first conflict to the lowest alternative. For a grammar whose conflict
  # subsets disagree on their minimum (e.g. `{{1,3},{2,4}}`) the reference
  # could keep scanning and settle on a different alternative; no tested
  # grammar (including the real SQLite/Erlang/Elixir grammars) exhibits this,
  # and matching the reference would reintroduce the unbounded-rescan blow-up
  # that Seed's lack of a persisted DFA makes costly (see
  # `Seed.ATN.PredictionMode.conflict?/2`). This is a deliberate divergence.
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
    case stop_state_alts(atn, configs) do
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

  # Takes and returns a config *list* (the interned state currency). Internally
  # it still builds a `ParserATNConfigSet` so configs merge/dedup correctly,
  # then returns its config list.
  defp compute_reach_set(atn, configs, t, parser, full_ctx?) do
    intermediate = reachable_configs(atn, configs, t, full_ctx?)

    {reach, _busy} =
      Enum.reduce(intermediate, {ParserATNConfigSet.new(full_ctx?), MapSet.new()}, fn config,
                                                                                      acc ->
        closure(atn, config, acc, false, parser, full_ctx?)
      end)

    ParserATNConfigSet.configs(reach)
  end

  defp reachable_configs(atn, configs, t, full_ctx?) do
    Enum.flat_map(configs, &reachable_from(atn, &1, t, full_ctx?))
  end

  # A config at a rule stop consumes nothing. In full context it is dropped
  # here (its caller follow was already consed into the closure). In SLL it is
  # *carried forward* — an alternative that reached the decision's rule end
  # stays alive so it can either be the unique survivor (a clean exit, no LL)
  # or conflict with a consuming alternative (deferring to LL). This is the
  # crux that makes the context-sensitive `ctx_b` case resolve correctly.
  defp reachable_from(atn, config, t, full_ctx?) do
    case Map.fetch!(atn.states, config.state) do
      %State{state_type: :rule_stop} ->
        if full_ctx?, do: [], else: [config]

      state ->
        for transition <- state.transitions,
            matches?(transition, t),
            do: %{config | state: transition.target}
    end
  end

  # --- Closure ------------------------------------------------------------

  defp closure(atn, config, acc, collect, parser, full_ctx?) do
    closure_checking_stop_state(atn, config, acc, collect, 0, parser, full_ctx?)
  end

  defp closure_checking_stop_state(
         atn,
         config,
         {configs, busy},
         collect,
         depth,
         parser,
         full_ctx?
       ) do
    if count_step() or ParserATNConfigSet.size(configs) >= @max_closure_configs or over_heap?(),
      do: prediction_overflow(parser)

    case Map.fetch!(atn.states, config.state) do
      %State{state_type: :rule_stop} ->
        closure_at_stop(atn, config, {configs, busy}, collect, depth, parser, full_ctx?)

      state ->
        closure_step(atn, config, state, {configs, busy}, collect, depth, parser, full_ctx?)
    end
  end

  defp closure_at_stop(atn, config, {configs, busy}, collect, depth, parser, full_ctx?) do
    if PredictionContext.empty?(config.context) do
      # An empty context at a rule stop means the closure fell off the end of
      # the decision's rule into the unknown outer context. In SLL that config
      # is marked as dipping (so a conflict can be deferred to LL); in full
      # context the real caller follow has already been consed in, so it is a
      # genuine accepting config and stays unmarked.
      {ParserATNConfigSet.add(configs, fell_off(config, full_ctx?)), busy}
    else
      pop_context(atn, config, {configs, busy}, collect, depth, parser, full_ctx?)
    end
  end

  defp pop_context(atn, config, acc, collect, depth, parser, full_ctx?) do
    Enum.reduce(0..(PredictionContext.size(config.context) - 1), acc, fn index, {configs, busy} ->
      return_state = PredictionContext.return_state(config.context, index)

      if return_state == PredictionContext.empty_return_state() do
        {ParserATNConfigSet.add(configs, fell_off(%{config | context: :empty}, full_ctx?)), busy}
      else
        popped = %{
          config
          | state: return_state,
            context: PredictionContext.parent(config.context, index)
        }

        closure_checking_stop_state(
          atn,
          popped,
          {configs, busy},
          collect,
          depth - 1,
          parser,
          full_ctx?
        )
      end
    end)
  end

  # Marks a configuration that fell off the decision's rule into the unknown
  # outer context. In full context this is a no-op (the real follow is known);
  # in SLL it increments `reaches_into_outer_context`, which the config set
  # surfaces as `dips_into_outer_context` for the conflict-vs-dip decision.
  defp fell_off(config, true), do: config

  defp fell_off(config, false),
    do: %{config | reaches_into_outer_context: config.reaches_into_outer_context + 1}

  defp closure_step(atn, config, state, {configs, busy}, collect, depth, parser, full_ctx?) do
    configs =
      if has_non_epsilon?(state), do: ParserATNConfigSet.add(configs, config), else: configs

    Enum.reduce(state.transitions, {configs, busy}, fn transition, acc ->
      follow_epsilon(atn, config, transition, acc, collect, depth, parser, full_ctx?)
    end)
  end

  defp follow_epsilon(atn, config, transition, {configs, busy}, collect, depth, parser, full_ctx?) do
    case epsilon_target(config, transition, collect, depth == 0) do
      nil ->
        {configs, busy}

      target ->
        visit_target(atn, target, transition, {configs, busy}, collect, depth, parser, full_ctx?)
    end
  end

  defp visit_target(atn, target, transition, {configs, busy}, collect, depth, parser, full_ctx?) do
    if MapSet.member?(busy, target) do
      {configs, busy}
    else
      descend(atn, target, transition, {configs, busy}, collect, depth, parser, full_ctx?)
    end
  end

  defp descend(atn, target, transition, {configs, busy}, collect, depth, parser, full_ctx?) do
    new_depth = if transition.type == :rule, do: depth + 1, else: depth

    if new_depth > @max_recursion_depth, do: prediction_overflow(parser)

    closure_checking_stop_state(
      atn,
      target,
      {configs, MapSet.put(busy, target)},
      collect,
      new_depth,
      parser,
      full_ctx?
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
