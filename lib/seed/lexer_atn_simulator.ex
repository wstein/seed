defmodule Seed.LexerATNSimulator do
  @moduledoc """
  Matches a single token by simulating the lexer ATN over a character
  stream.

  This is a faithful transliteration of the reference `LexerATNSimulator`
  with one deliberate omission: it does **not** build the adaptive DFA
  cache. The DFA is pure memoization of decisions the ATN already makes, so
  omitting it yields identical results, only recomputed each time. A
  BEAM-native cache (ETS, per the ADR-005 decision) is a later optimization
  that does not change behavior.

  The algorithm is otherwise the reference one: compute the epsilon-closure
  of the mode's start state, then repeatedly compute the set of
  configurations reachable on the next input symbol, consuming input and
  remembering the most recent accepting state. When no symbol can be
  consumed, it rolls back to that best match (longest match; ties broken by
  rule order).

  `match/5` is pure: it takes the current stream and position and returns
  the matched token type, the accumulated lexer actions, and the advanced
  stream and position.
  """

  alias Seed.ATN

  alias Seed.ATN.{
    ATNConfig,
    ATNConfigSet,
    LexerActionExecutor,
    PredictionContext,
    State,
    Transition
  }

  alias Seed.CharStream
  alias Seed.IntervalSet

  @eof Seed.Token.eof()

  @typedoc "The result of matching one token."
  @type result ::
          {:ok, token_type :: integer(), LexerActionExecutor.t() | nil, CharStream.t(),
           line :: pos_integer(), column :: non_neg_integer()}
          | {:eof, CharStream.t(), pos_integer(), non_neg_integer()}
          | {:no_viable, CharStream.t(), non_neg_integer(), pos_integer(), non_neg_integer()}

  # The best accepting state seen so far during one match.
  defmodule SimState do
    @moduledoc false
    @enforce_keys [:index, :line, :column, :token_type, :executor]
    defstruct [:index, :line, :column, :token_type, :executor]
  end

  @doc """
  Matches one token in `mode` starting at the current position of `input`.

  `line` and `column` are the position of the current character. Returns
  `{:ok, token_type, executor, input, line, column}` with `input` advanced
  to just past the matched token; `{:eof, ...}` at end of input; or
  `{:no_viable, ...}` when no rule matches.
  """
  @spec match(ATN.t(), CharStream.t(), non_neg_integer(), pos_integer(), non_neg_integer()) ::
          result()
  def match(%ATN{} = atn, input, mode, line, column) do
    start_index = CharStream.index(input)
    start_number = Enum.at(atn.mode_to_start_state, mode)
    start_state = Map.fetch!(atn.states, start_number)
    configs = compute_start_state(atn, start_state)

    t = CharStream.la(input, 1)
    accept = capture_accept(atn, configs, input, line, column, nil)
    exec_atn(atn, input, configs, t, line, column, start_index, accept)
  end

  defp compute_start_state(atn, start_state) do
    start_state.transitions
    |> Enum.with_index()
    |> Enum.reduce(ATNConfigSet.new(), fn {transition, index}, configs ->
      config =
        new_config(atn, transition.target, index + 1, PredictionContext.empty(), nil, false)

      {_reached, configs} = closure(atn, config, configs, false, false)
      configs
    end)
  end

  # --- Main loop ----------------------------------------------------------

  defp exec_atn(atn, input, configs, t, line, column, start_index, accept) do
    reach = compute_reach_set(atn, configs, t)

    if ATNConfigSet.empty?(reach) do
      fail_or_accept(accept, input, t, line, column, start_index)
    else
      {input, line, column} = consume_unless_eof(input, t, line, column)
      accept = capture_accept(atn, reach, input, line, column, accept)

      if t == @eof do
        fail_or_accept(accept, input, CharStream.la(input, 1), line, column, start_index)
      else
        exec_atn(atn, input, reach, CharStream.la(input, 1), line, column, start_index, accept)
      end
    end
  end

  defp consume_unless_eof(input, @eof, line, column), do: {input, line, column}

  defp consume_unless_eof(input, ?\n, line, _column), do: {CharStream.consume(input), line + 1, 0}

  defp consume_unless_eof(input, _t, line, column),
    do: {CharStream.consume(input), line, column + 1}

  defp fail_or_accept(%SimState{} = accept, input, _t, _line, _column, _start_index) do
    {:ok, accept.token_type, accept.executor, CharStream.seek(input, accept.index), accept.line,
     accept.column}
  end

  defp fail_or_accept(nil, input, @eof, line, column, start_index) do
    if CharStream.index(input) == start_index do
      {:eof, input, line, column}
    else
      {:no_viable, input, start_index, line, column}
    end
  end

  defp fail_or_accept(nil, input, _t, line, column, start_index) do
    {:no_viable, input, start_index, line, column}
  end

  defp capture_accept(atn, configs, input, line, column, previous) do
    case first_accept(atn, configs) do
      nil ->
        previous

      {token_type, executor} ->
        %SimState{
          index: CharStream.index(input),
          line: line,
          column: column,
          token_type: token_type,
          executor: executor
        }
    end
  end

  defp first_accept(atn, configs) do
    Enum.find_value(ATNConfigSet.configs(configs), fn config ->
      case Map.fetch!(atn.states, config.state) do
        %State{state_type: :rule_stop, rule_index: rule_index} ->
          {Enum.at(atn.rule_to_token_type, rule_index), config.lexer_action_executor}

        _state ->
          nil
      end
    end)
  end

  # --- Reach --------------------------------------------------------------

  defp compute_reach_set(atn, configs, t) do
    treat_eof = t == @eof

    {reach, _skip_alt} =
      Enum.reduce(ATNConfigSet.configs(configs), {ATNConfigSet.new(), 0}, fn config,
                                                                             {reach, skip_alt} ->
        if config.alt == skip_alt and config.passed_through_non_greedy do
          {reach, skip_alt}
        else
          reach_from(atn, config, t, treat_eof, reach, skip_alt)
        end
      end)

    reach
  end

  defp reach_from(atn, config, t, treat_eof, reach, skip_alt) do
    state = Map.fetch!(atn.states, config.state)
    current_alt_reached = config.alt == skip_alt

    Enum.reduce_while(state.transitions, {reach, skip_alt}, fn transition, acc ->
      reach_transition(atn, config, transition, t, treat_eof, current_alt_reached, acc)
    end)
  end

  defp reach_transition(
         atn,
         config,
         transition,
         t,
         treat_eof,
         current_alt_reached,
         {reach, skip_alt}
       ) do
    if matches?(transition, t) do
      target =
        new_config(
          atn,
          transition.target,
          config.alt,
          config.context,
          config.lexer_action_executor,
          config.passed_through_non_greedy
        )

      case closure(atn, target, reach, current_alt_reached, treat_eof) do
        {true, reach} -> {:halt, {reach, config.alt}}
        {false, reach} -> {:cont, {reach, skip_alt}}
      end
    else
      {:cont, {reach, skip_alt}}
    end
  end

  # --- Closure ------------------------------------------------------------

  defp closure(atn, %ATNConfig{} = config, configs, current_alt_reached, treat_eof) do
    case Map.fetch!(atn.states, config.state) do
      %State{state_type: :rule_stop} = state ->
        closure_at_stop(atn, config, state, configs, current_alt_reached, treat_eof)

      state ->
        closure_step(atn, config, state, configs, current_alt_reached, treat_eof)
    end
  end

  defp closure_at_stop(atn, config, _state, configs, current_alt_reached, treat_eof) do
    case config.context do
      :empty ->
        {true, ATNConfigSet.add(configs, config)}

      %PredictionContext{parent: parent, return_state: return_state} ->
        popped =
          new_config(
            atn,
            return_state,
            config.alt,
            parent,
            config.lexer_action_executor,
            config.passed_through_non_greedy
          )

        closure(atn, popped, configs, current_alt_reached, treat_eof)
    end
  end

  defp closure_step(atn, config, state, configs, current_alt_reached, treat_eof) do
    configs =
      if consuming?(state) and not (current_alt_reached and config.passed_through_non_greedy) do
        ATNConfigSet.add(configs, config)
      else
        configs
      end

    Enum.reduce(state.transitions, {current_alt_reached, configs}, fn transition,
                                                                      {reached, configs} ->
      case epsilon_target(atn, config, transition, treat_eof) do
        nil -> {reached, configs}
        target -> closure(atn, target, configs, reached, treat_eof)
      end
    end)
  end

  # --- Epsilon successors -------------------------------------------------

  defp epsilon_target(atn, config, %Transition{type: :rule} = transition, _treat_eof) do
    context = PredictionContext.singleton(config.context, transition.follow_state)

    new_config(
      atn,
      transition.target,
      config.alt,
      context,
      config.lexer_action_executor,
      config.passed_through_non_greedy
    )
  end

  defp epsilon_target(_atn, _config, %Transition{type: :precedence}, _treat_eof) do
    raise ArgumentError, "precedence predicates are not valid in a lexer"
  end

  defp epsilon_target(_atn, _config, %Transition{type: :predicate}, _treat_eof) do
    raise ArgumentError, "lexer semantic predicates are not supported yet"
  end

  defp epsilon_target(atn, config, %Transition{type: :action} = transition, _treat_eof) do
    executor = action_executor(atn, config, transition)

    new_config(
      atn,
      transition.target,
      config.alt,
      config.context,
      executor,
      config.passed_through_non_greedy
    )
  end

  defp epsilon_target(atn, config, %Transition{type: :epsilon} = transition, _treat_eof) do
    new_config(
      atn,
      transition.target,
      config.alt,
      config.context,
      config.lexer_action_executor,
      config.passed_through_non_greedy
    )
  end

  defp epsilon_target(atn, config, transition, true) do
    if matches?(transition, @eof) do
      new_config(
        atn,
        transition.target,
        config.alt,
        config.context,
        config.lexer_action_executor,
        config.passed_through_non_greedy
      )
    else
      nil
    end
  end

  defp epsilon_target(_atn, _config, _transition, false), do: nil

  # Lexer actions only attach while still in the start rule (empty context).
  defp action_executor(atn, %ATNConfig{context: :empty} = config, %Transition{action_index: index})
       when index >= 0 do
    case Enum.at(atn.lexer_actions, index) do
      nil -> config.lexer_action_executor
      action -> LexerActionExecutor.append(config.lexer_action_executor, action)
    end
  end

  defp action_executor(_atn, config, _transition), do: config.lexer_action_executor

  # --- Symbol matching ----------------------------------------------------

  defp matches?(%Transition{type: :atom, label: label}, symbol), do: symbol == label

  defp matches?(%Transition{type: :range, from: from, to: to}, symbol),
    do: symbol >= from and symbol <= to

  defp matches?(%Transition{type: :set, set: set}, symbol), do: IntervalSet.member?(set, symbol)

  defp matches?(%Transition{type: :not_set, set: set}, symbol) do
    symbol != @eof and not IntervalSet.member?(set, symbol)
  end

  defp matches?(%Transition{type: :wildcard}, symbol), do: symbol != @eof
  defp matches?(%Transition{}, _symbol), do: false

  defp consuming?(%State{transitions: transitions}) do
    Enum.any?(transitions, &(not Transition.epsilon?(&1)))
  end

  # --- Config construction ------------------------------------------------

  defp new_config(atn, state_number, alt, context, executor, source_passed_non_greedy) do
    state = Map.fetch!(atn.states, state_number)
    passed = source_passed_non_greedy or (State.decision?(state.state_type) and state.non_greedy)

    %ATNConfig{
      state: state_number,
      alt: alt,
      context: context,
      lexer_action_executor: executor,
      passed_through_non_greedy: passed
    }
  end
end
