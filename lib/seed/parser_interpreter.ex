defmodule Seed.ParserInterpreter do
  @moduledoc """
  Builds a parse tree by walking the ATN, mirroring ANTLR's
  `ParserInterpreter`.

  It moves a pointer through the ATN: at a decision state it asks
  `Seed.ParserATNSimulator` which alternative to take, then follows the
  transition — matching a token, entering a sub-rule, or (for left-recursive
  rules) renesting the context. The result is a `Seed.ParserRuleContext`
  tree, renderable with `Seed.Trees`.

  No generated code is required: the ATN plus the simulator are enough to
  parse.
  """

  alias Seed.ATN
  alias Seed.ATN.State
  alias Seed.Diagnostic
  alias Seed.Grammar
  alias Seed.Parser
  alias Seed.ParserATNSimulator
  alias Seed.ParserRuleContext
  alias Seed.TokenStream
  alias Seed.Vocabulary

  @doc """
  Parses `token_stream` starting at `start_rule_index`.

  Accepts a `Seed.Grammar` (using its ATN and vocabulary) or a bare
  `Seed.ATN`. Returns `{:ok, tree}` for well-formed input, or
  `{:error, diagnostics, tree}` when recovery was needed — the parser always
  produces a complete tree (errors are recovered), so the partial tree, with
  `Seed.ErrorNode` leaves marking the recovery points, is returned alongside
  the diagnostics.

  Options:

    * `:sempred` — a `t:Seed.Parser.sempred/0` evaluating grammar semantic
      predicates `{...}?`; defaults to treating every predicate as satisfied.
    * `:bail` — when `true`, abort at the first error (the reference
      `BailErrorStrategy`) and return `{:error, [diagnostic]}` with no tree,
      instead of recovering. Defaults to `false`.
  """
  @spec parse(Grammar.t() | ATN.t(), TokenStream.t(), non_neg_integer(), keyword()) ::
          {:ok, ParserRuleContext.t()}
          | {:error, [Diagnostic.t()]}
          | {:error, [Diagnostic.t()], ParserRuleContext.t()}
  def parse(grammar_or_atn, token_stream, start_rule_index, opts \\ [])

  def parse(
        %Grammar{atn: atn, vocabulary: vocabulary},
        %TokenStream{} = token_stream,
        start_rule_index,
        opts
      ) do
    do_parse(atn, token_stream, start_rule_index, vocabulary, opts)
  end

  def parse(%ATN{} = atn, %TokenStream{} = token_stream, start_rule_index, opts) do
    do_parse(atn, token_stream, start_rule_index, Vocabulary.empty(), opts)
  end

  defp do_parse(atn, token_stream, start_rule_index, vocabulary, opts) do
    {tree, parser} = build_tree(atn, token_stream, start_rule_index, vocabulary, opts)

    case parser.diagnostics do
      [] -> {:ok, tree}
      diagnostics -> {:error, diagnostics, tree}
    end
  catch
    # Bail mode aborts at the first error with that single diagnostic.
    {:seed_bail, diagnostic} -> {:error, [diagnostic]}
  end

  defp build_tree(atn, token_stream, start_rule_index, vocabulary, opts) do
    parser =
      case Keyword.get(opts, :sempred) do
        nil -> Parser.new(atn, token_stream, vocabulary)
        sempred -> Parser.new(atn, token_stream, vocabulary, sempred)
      end

    error_mode = if Keyword.get(opts, :bail, false), do: :bail, else: :recover
    parser = %{parser | error_mode: error_mode}

    start_number = Enum.at(atn.rule_to_start_state, start_rule_index)
    start_state = Map.fetch!(atn.states, start_number)
    push_states = precedence_decision_states(atn)

    parser =
      if start_state.is_precedence_rule do
        Parser.enter_recursion_rule(parser, start_number, start_rule_index, -1, 0)
      else
        Parser.enter_rule(parser, start_number, start_rule_index, -1)
      end

    run(parser, atn, push_states)
  end

  defp run(parser, atn, push_states) do
    do_run(parser, atn, push_states)
  catch
    # An unrecoverable single-token error throws the parser back here for
    # panic-mode recovery: resynchronize to the current rule's follow set,
    # then resume the walk (which unwinds via the rule's stop state).
    {:seed_resync, recovered} ->
      recovered |> Parser.sync() |> run(atn, push_states)
  end

  defp do_run(parser, atn, push_states) do
    state = Map.fetch!(atn.states, parser.state)

    case state.state_type do
      :rule_stop ->
        at_rule_stop(parser, atn, state, push_states)

      _other ->
        parser
        |> visit_state(atn, state, push_states)
        |> do_run(atn, push_states)
    end
  end

  defp at_rule_stop(parser, atn, state, push_states) do
    if Parser.current_context(parser).invoking_state == -1 do
      # The start rule's context is the finished tree; seal it (its children
      # were built reversed) and return it with the parser so accumulated
      # diagnostics can be surfaced.
      {ParserRuleContext.seal(Parser.current_context(parser)), parser}
    else
      parser |> visit_rule_stop_state(atn, state) |> run(atn, push_states)
    end
  end

  # --- Visiting a state ---------------------------------------------------

  # Single transition (the common, non-decision case): no prediction, no list
  # scan.
  defp visit_state(parser, atn, %State{transitions: [transition]} = state, push_states) do
    parser = apply_transition(parser, atn, state, transition, push_states)
    %{parser | state: transition.target}
  end

  defp visit_state(parser, atn, %State{transitions: transitions} = state, push_states) do
    edge = ParserATNSimulator.adaptive_predict(parser, state.decision)
    transition = Enum.at(transitions, edge - 1)
    parser = apply_transition(parser, atn, state, transition, push_states)
    %{parser | state: transition.target}
  end

  defp apply_transition(parser, atn, state, %{type: :epsilon} = transition, push_states) do
    if MapSet.member?(push_states, state.state_number) and
         Map.fetch!(atn.states, transition.target).state_type != :loop_end do
      invoking = hd(parser.parent_context_stack)

      Parser.push_new_recursion_context(
        parser,
        Parser.current_context(parser).rule_index,
        invoking
      )
    else
      parser
    end
  end

  defp apply_transition(parser, _atn, _state, %{type: :atom, label: label}, _push_states) do
    Parser.match(parser, label)
  end

  defp apply_transition(parser, _atn, _state, %{type: :wildcard}, _push_states) do
    Parser.match_wildcard(parser)
  end

  defp apply_transition(parser, _atn, _state, %{type: type}, _push_states)
       when type in [:range, :set, :not_set] do
    Parser.match_wildcard(parser)
  end

  defp apply_transition(parser, atn, state, %{type: :rule} = transition, _push_states) do
    rule_start = Map.fetch!(atn.states, transition.target)

    if rule_start.is_precedence_rule do
      Parser.enter_recursion_rule(
        parser,
        transition.target,
        rule_start.rule_index,
        state.state_number,
        transition.precedence
      )
    else
      Parser.enter_rule(parser, transition.target, rule_start.rule_index, state.state_number)
    end
  end

  # Predicates, actions, and precedence guards: the interpreter cannot run
  # generated code, but the simulator has already chosen a viable
  # alternative, so these are no-ops on the matched path.
  defp apply_transition(parser, _atn, _state, %{type: type}, _push_states)
       when type in [:predicate, :action, :precedence] do
    parser
  end

  # --- Returning from a rule ----------------------------------------------

  defp visit_rule_stop_state(parser, atn, state) do
    rule_start = Map.fetch!(atn.states, Enum.at(atn.rule_to_start_state, state.rule_index))

    parser =
      if rule_start.is_precedence_rule do
        invoking = hd(parser.parent_context_stack)
        {_result, parser} = Parser.unroll_recursion_contexts(parser)
        %{parser | state: invoking}
      else
        Parser.exit_rule(parser)
      end

    rule_transition = hd(Map.fetch!(atn.states, parser.state).transitions)
    %{parser | state: rule_transition.follow_state}
  end

  defp precedence_decision_states(atn) do
    atn.states
    |> Map.values()
    |> Enum.filter(fn
      %State{state_type: :star_loop_entry, is_precedence_decision: true} -> true
      _state -> false
    end)
    |> MapSet.new(& &1.state_number)
  end
end
