defmodule Seed.Parser do
  @moduledoc """
  The mutable-looking parser state, threaded immutably.

  This holds what the reference `Parser` mutates while building a parse
  tree: the current ATN `state`, the token `input`, a stack of context
  `frames` (the top frame is the current rule context), the
  `precedence_stack` for left-recursive rules, and the
  `parent_context_stack` recording where each recursion was entered.

  The context frames double as the parse tree: each is a
  `Seed.ParserRuleContext` accumulating children. Entering a rule pushes a
  frame; a token is appended to the top frame; leaving a rule pops the
  frame and appends it to its parent. Left recursion is a renesting of the
  top frame (see `push_new_recursion_context/3`).

  Every operation returns an updated parser; nothing is mutated in place.
  """

  alias Seed.ATN
  alias Seed.ATN.State
  alias Seed.ATN.Transition
  alias Seed.Diagnostic
  alias Seed.ErrorNode
  alias Seed.ParserRuleContext
  alias Seed.TerminalNode
  alias Seed.Token
  alias Seed.TokenStream
  alias Seed.Vocabulary

  @eof Token.eof()

  @typedoc """
  Evaluates a grammar semantic predicate `{...}?`.

  Called with the predicate's rule index, its per-rule predicate index, and
  the current rule context, it returns whether the predicate holds. The
  interpreter cannot run the host code a predicate compiles to, so the caller
  supplies this; the default treats every predicate as satisfied.
  """
  @type sempred :: (rule_index :: integer(), pred_index :: integer(), ParserRuleContext.t() ->
                      boolean())

  @type t :: %__MODULE__{
          atn: ATN.t(),
          input: TokenStream.t(),
          vocabulary: Vocabulary.t(),
          state: integer(),
          frames: [ParserRuleContext.t()],
          precedence_stack: [integer()],
          parent_context_stack: [integer()],
          diagnostics: [Diagnostic.t()],
          sempred: sempred(),
          error_mode: error_mode()
        }

  @typedoc """
  How the parser reacts to a syntax error.

    * `:recover` (default) — accumulate a diagnostic and recover (single-token
      deletion/insertion or panic-mode resynchronization), so one parse
      reports every error and still yields a tree.
    * `:bail` — abort at the first error with that single diagnostic and no
      tree, the equivalent of the reference `BailErrorStrategy`.
  """
  @type error_mode :: :recover | :bail

  @enforce_keys [:atn, :input]
  defstruct atn: nil,
            input: nil,
            vocabulary: nil,
            state: -1,
            frames: [],
            precedence_stack: [],
            parent_context_stack: [],
            diagnostics: [],
            sempred: nil,
            error_mode: :recover

  @doc """
  Builds a parser over `atn` reading `input`.

  `vocabulary` supplies token names for diagnostics; it defaults to an empty
  vocabulary, in which case messages fall back to numeric token types.
  `sempred` evaluates grammar semantic predicates (see `t:sempred/0`); it
  defaults to treating every predicate as satisfied.
  """
  @spec new(ATN.t(), TokenStream.t(), Vocabulary.t(), sempred()) :: t()
  def new(
        %ATN{} = atn,
        %TokenStream{} = input,
        vocabulary \\ Vocabulary.empty(),
        sempred \\ &default_sempred/3
      ) do
    %__MODULE__{atn: atn, input: input, vocabulary: vocabulary, sempred: sempred}
  end

  # The default predicate evaluator: every semantic predicate is satisfied,
  # which reproduces the behaviour of a grammar without predicates.
  defp default_sempred(_rule_index, _pred_index, _ctx), do: true

  @doc "The current rule context (the top frame)."
  @spec current_context(t()) :: ParserRuleContext.t()
  def current_context(%__MODULE__{frames: [ctx | _]}), do: ctx

  @doc "The precedence at the top of the precedence stack (0 if empty)."
  @spec precedence(t()) :: integer()
  def precedence(%__MODULE__{precedence_stack: [p | _]}), do: p
  def precedence(%__MODULE__{precedence_stack: []}), do: 0

  @doc "Enters a normal rule, pushing a new context frame."
  @spec enter_rule(t(), integer(), non_neg_integer(), integer()) :: t()
  def enter_rule(parser, state, rule_index, invoking_state) do
    %{
      parser
      | state: state,
        frames: [ParserRuleContext.new(rule_index, invoking_state) | parser.frames]
    }
  end

  @doc "Enters a left-recursive rule, also pushing precedence and recursion bookkeeping."
  @spec enter_recursion_rule(t(), integer(), non_neg_integer(), integer(), integer()) :: t()
  def enter_recursion_rule(parser, state, rule_index, invoking_state, precedence) do
    %{
      parser
      | state: state,
        precedence_stack: [precedence | parser.precedence_stack],
        parent_context_stack: [invoking_state | parser.parent_context_stack],
        frames: [ParserRuleContext.new(rule_index, invoking_state) | parser.frames]
    }
  end

  @doc """
  Renests the current frame as the first child of a fresh recursion frame.

  This is how a left-recursive rule grows a left-leaning tree: the
  expression parsed so far becomes a child of the next iteration's context.
  """
  @spec push_new_recursion_context(t(), non_neg_integer(), integer()) :: t()
  def push_new_recursion_context(
        %__MODULE__{frames: [previous | rest]} = parser,
        rule_index,
        invoking_state
      ) do
    # `previous` is finished being built, so seal it before it becomes a
    # child of the new recursion frame.
    wrapper =
      rule_index
      |> ParserRuleContext.new(invoking_state)
      |> ParserRuleContext.prepend_child(ParserRuleContext.seal(previous))

    %{parser | frames: [wrapper | rest]}
  end

  @doc """
  Matches the current token against `token_type` and consumes it.

  On a mismatch it attempts, in order, two single-token recoveries before
  giving up:

    * *deletion* — if the *next* token is the expected one, the current
      token is reported as extraneous and dropped; and
    * *insertion* — if the current token can continue the rule once the
      expected token is supplied, the expected token is reported as missing
      and parsing proceeds without consuming.

  Insertion is only attempted when the current token is reachable past the
  expected one, following the rule-invocation context into the caller (an ATN
  check, `expects_in_context?/4`), which keeps it from looping. When neither
  single-token recovery applies, the parser is thrown back for panic-mode
  resynchronization (see `sync/1`).
  """
  @spec match(t(), integer()) :: t()
  def match(%__MODULE__{} = parser, token_type) do
    token = TokenStream.lt(parser.input, 1)

    cond do
      token.type == token_type ->
        consume(parser)

      # In bail mode a mismatch aborts immediately, without single-token
      # recovery.
      parser.error_mode == :bail ->
        fail(parser, token_mismatch(parser, token, token_type))

      TokenStream.la(parser.input, 2) == token_type ->
        delete_extraneous_token(parser, token)

      can_insert?(parser, token_type, token.type) ->
        insert_missing_token(parser, token, token_type)

      true ->
        fail(parser, token_mismatch(parser, token, token_type))
    end
  end

  @doc "Matches any non-EOF token (a wildcard) and consumes it."
  @spec match_wildcard(t()) :: t()
  def match_wildcard(%__MODULE__{} = parser) do
    token = TokenStream.lt(parser.input, 1)

    if token.type > 0 do
      consume(parser)
    else
      fail(
        parser,
        Diagnostic.error(
          :input_mismatch,
          "mismatched input #{describe(token)}, expected any token",
          line: token.line,
          column: token.column
        )
      )
    end
  end

  @doc "Records `diagnostic` (a recovered error) on the parser."
  @spec add_diagnostic(t(), Diagnostic.t()) :: t()
  def add_diagnostic(%__MODULE__{} = parser, %Diagnostic{} = diagnostic) do
    %{parser | diagnostics: parser.diagnostics ++ [diagnostic]}
  end

  # Reports the current token as extraneous, attaches it to the tree as an
  # error node, drops it, and matches the expected token that follows.
  defp delete_extraneous_token(parser, token) do
    diagnostic =
      Diagnostic.error(:extraneous_input, "extraneous input #{describe(token)}",
        line: token.line,
        column: token.column
      )

    parser
    |> add_diagnostic(diagnostic)
    |> add_child(ErrorNode.new(token))
    |> Map.update!(:input, &TokenStream.consume/1)
    |> consume()
  end

  # Single-token insertion is viable when the grammar has a transition for
  # the expected token out of the current state and, past that token, the
  # *current* token can still continue — following the rule-invocation context
  # into the caller, as ANTLR's `nextTokens(next, ctx)` does. That second
  # check is what keeps insertion from looping: a fabricated token is only
  # accepted when it lets real input make progress. The context is essential
  # when the expected token ends a rule (e.g. a trailing `;`): the token that
  # may follow it lives in the caller (e.g. `EOF` after a `stat` in `prog`).
  defp can_insert?(parser, expected_type, current_type) do
    case next_state_after(parser, expected_type) do
      nil -> false
      next -> expects_in_context?(parser.atn, next, current_type, parser.frames)
    end
  end

  # The target of the (single) consuming transition out of `parser.state`
  # that matches `expected_type`, or `nil` when none does.
  defp next_state_after(parser, expected_type) do
    parser.atn.states
    |> Map.fetch!(parser.state)
    |> Map.fetch!(:transitions)
    |> Enum.find_value(fn transition ->
      if not Transition.epsilon?(transition) and Transition.matches?(transition, expected_type) do
        transition.target
      end
    end)
  end

  # Reports the expected token as missing, attaches a fabricated `<missing …>`
  # error node in its place, and continues *without* consuming, so the
  # current (real) token is matched next.
  defp insert_missing_token(parser, token, expected_type) do
    name = Vocabulary.display_name(parser.vocabulary, expected_type)

    diagnostic =
      Diagnostic.error(:missing_token, "missing #{name} at #{describe(token)}",
        line: token.line,
        column: token.column
      )

    missing =
      Token.new(expected_type, text: "<missing #{name}>", line: token.line, column: token.column)

    parser
    |> add_diagnostic(diagnostic)
    |> add_child(ErrorNode.new(missing))
  end

  # Walks the epsilon-closure of `state` (epsilon, rule, action, predicate,
  # precedence edges) and returns `true` when any reachable *consuming*
  # transition matches `symbol`. Rule-stop states and already-visited states
  # terminate the walk, bounding it to the rule's local reachability.
  defp expects?(atn, state_number, symbol) do
    expects?(atn, state_number, symbol, %{})
  end

  defp expects?(atn, state_number, symbol, visited) do
    if Map.has_key?(visited, state_number) do
      false
    else
      visited = Map.put(visited, state_number, true)

      case Map.fetch!(atn.states, state_number) do
        %State{state_type: :rule_stop} ->
          false

        %State{transitions: transitions} ->
          Enum.any?(transitions, &transition_expects?(atn, &1, symbol, visited))
      end
    end
  end

  defp transition_expects?(atn, transition, symbol, visited) do
    if Transition.epsilon?(transition) do
      expects?(atn, transition.target, symbol, visited)
    else
      Transition.matches?(transition, symbol)
    end
  end

  # Like `expects?/3`, but at a rule-stop it follows the return into the caller
  # (using the active frame stack) instead of giving up — the faithful analogue
  # of ANTLR's `ATN.nextTokens(state, context)`. `frames` is the rule stack
  # whose head is the rule the walk is currently inside.
  defp expects_in_context?(atn, state_number, symbol, frames),
    do: expects_in_context?(atn, state_number, symbol, frames, %{})

  defp expects_in_context?(atn, state_number, symbol, frames, visited) do
    key = {state_number, length(frames)}

    if Map.has_key?(visited, key) do
      false
    else
      visited = Map.put(visited, key, true)

      case Map.fetch!(atn.states, state_number) do
        %State{state_type: :rule_stop} ->
          follow_return_expects?(atn, symbol, frames, visited)

        %State{transitions: transitions} ->
          Enum.any?(
            transitions,
            &transition_expects_in_context?(atn, &1, symbol, frames, visited)
          )
      end
    end
  end

  defp transition_expects_in_context?(atn, transition, symbol, frames, visited) do
    if Transition.epsilon?(transition) do
      expects_in_context?(atn, transition.target, symbol, frames, visited)
    else
      Transition.matches?(transition, symbol)
    end
  end

  # Pop the current rule and continue the walk from the caller's follow state.
  defp follow_return_expects?(_atn, _symbol, [], _visited), do: false

  defp follow_return_expects?(
         _atn,
         _symbol,
         [%ParserRuleContext{invoking_state: -1} | _],
         _visited
       ),
       do: false

  defp follow_return_expects?(
         atn,
         symbol,
         [%ParserRuleContext{invoking_state: invoking} | rest],
         visited
       ) do
    follow = hd(Map.fetch!(atn.states, invoking).transitions).follow_state
    expects_in_context?(atn, follow, symbol, rest, visited)
  end

  defp token_mismatch(parser, token, token_type) do
    Diagnostic.error(
      :token_mismatch,
      "mismatched input #{describe(token)}, expected #{Vocabulary.display_name(parser.vocabulary, token_type)}",
      line: token.line,
      column: token.column
    )
  end

  # Reports an unrecoverable error. In `:bail` mode it aborts the parse with
  # the single diagnostic; otherwise it throws the parser back to the
  # interpreter for panic-mode resynchronization (`sync/1`).
  @spec fail(t(), Diagnostic.t()) :: no_return()
  defp fail(%__MODULE__{error_mode: :bail}, diagnostic) do
    throw({:seed_bail, diagnostic})
  end

  defp fail(parser, diagnostic) do
    throw({:seed_resync, add_diagnostic(parser, diagnostic)})
  end

  @doc """
  Panic-mode recovery: discards input up to the current rule's follow set,
  then positions the parser at that rule's stop state so the walk unwinds to
  the caller.

  The follow (resynchronization) set is the union, over the active rule
  frames, of the tokens that can appear after each rule — computed from the
  ATN with `expects?/3`. Tokens are dropped until the current one is in that
  set or end-of-input is reached. Because every recovery either consumes a
  token or pops a rule, resynchronization always makes progress.
  """
  @spec sync(t()) :: t()
  def sync(%__MODULE__{} = parser) do
    parser = consume_until_recovery(parser)
    %{parser | state: Enum.at(parser.atn.rule_to_stop_state, current_context(parser).rule_index)}
  end

  defp consume_until_recovery(parser) do
    if in_recovery_set?(parser, TokenStream.la(parser.input, 1)) do
      parser
    else
      parser
      |> add_child(ErrorNode.new(TokenStream.lt(parser.input, 1)))
      |> Map.update!(:input, &TokenStream.consume/1)
      |> consume_until_recovery()
    end
  end

  defp in_recovery_set?(parser, symbol) do
    symbol == @eof or Enum.any?(parser.frames, &recovers_at?(parser.atn, &1, symbol))
  end

  defp recovers_at?(_atn, %ParserRuleContext{invoking_state: -1}, _symbol), do: false

  defp recovers_at?(atn, %ParserRuleContext{invoking_state: invoking}, symbol) do
    follow = hd(Map.fetch!(atn.states, invoking).transitions).follow_state
    expects?(atn, follow, symbol)
  end

  defp describe(%Token{type: @eof}), do: "<EOF>"
  defp describe(%Token{text: nil, type: type}), do: "<#{type}>"
  defp describe(%Token{text: text}), do: inspect(text)

  @doc "Consumes the current token, appending it to the current frame."
  @spec consume(t()) :: t()
  def consume(%__MODULE__{} = parser) do
    token = TokenStream.lt(parser.input, 1)
    input = if token.type != @eof, do: TokenStream.consume(parser.input), else: parser.input
    add_child(%{parser | input: input}, TerminalNode.new(token))
  end

  @doc "Leaves a normal rule: pops the frame, returns to the caller, and reparents."
  @spec exit_rule(t()) :: t()
  def exit_rule(%__MODULE__{frames: [completed | rest]} = parser) do
    %{parser | state: completed.invoking_state, frames: rest}
    |> add_child(ParserRuleContext.seal(completed))
  end

  @doc """
  Unrolls a finished left-recursive rule, returning `{result, parser}`.

  The completed recursion frame is the result; it is reparented onto the
  caller's frame (if any), and the precedence/recursion stacks are popped.
  """
  @spec unroll_recursion_contexts(t()) :: {ParserRuleContext.t(), t()}
  def unroll_recursion_contexts(%__MODULE__{frames: [result | rest]} = parser) do
    parser = %{
      parser
      | frames: rest,
        precedence_stack: tl(parser.precedence_stack),
        parent_context_stack: tl(parser.parent_context_stack)
    }

    result = ParserRuleContext.seal(result)
    {result, add_child(parser, result)}
  end

  # Appends a child to the current frame; a no-op when there is no frame
  # (the root rule has no parent to reparent into).
  defp add_child(%__MODULE__{frames: []} = parser, _child), do: parser

  defp add_child(%__MODULE__{frames: [ctx | rest]} = parser, child) do
    %{parser | frames: [ParserRuleContext.prepend_child(ctx, child) | rest]}
  end
end
