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

  @doc """
  Parses `token_stream` starting at `start_rule_index`.

  Accepts a `Seed.Grammar` (using its ATN) or a bare `Seed.ATN`, and returns
  `{:ok, tree}` or `{:error, [Seed.Diagnostic.t()]}`.
  """
  @spec parse(Grammar.t() | ATN.t(), TokenStream.t(), non_neg_integer()) ::
          {:ok, ParserRuleContext.t()} | {:error, [Diagnostic.t()]}
  def parse(%Grammar{atn: atn}, %TokenStream{} = token_stream, start_rule_index) do
    parse(atn, token_stream, start_rule_index)
  end

  def parse(%ATN{} = atn, %TokenStream{} = token_stream, start_rule_index) do
    {:ok, build_tree(atn, token_stream, start_rule_index)}
  rescue
    error in Parser.Error -> {:error, [error.diagnostic]}
  end

  defp build_tree(atn, token_stream, start_rule_index) do
    parser = Parser.new(atn, token_stream)
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
    state = Map.fetch!(atn.states, parser.state)

    case state.state_type do
      :rule_stop ->
        at_rule_stop(parser, atn, state, push_states)

      _other ->
        parser
        |> visit_state(atn, state, push_states)
        |> run(atn, push_states)
    end
  end

  defp at_rule_stop(parser, atn, state, push_states) do
    if Parser.current_context(parser).invoking_state == -1 do
      # The start rule's context is the finished tree; stack cleanup would
      # only mutate the parser we are about to discard.
      Parser.current_context(parser)
    else
      parser |> visit_rule_stop_state(atn, state) |> run(atn, push_states)
    end
  end

  # --- Visiting a state ---------------------------------------------------

  defp visit_state(parser, atn, %State{transitions: transitions} = state, push_states) do
    edge =
      if length(transitions) > 1 do
        ParserATNSimulator.adaptive_predict(parser, state.decision)
      else
        1
      end

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
