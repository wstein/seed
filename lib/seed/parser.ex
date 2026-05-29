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
  alias Seed.Diagnostic
  alias Seed.ParserRuleContext
  alias Seed.TerminalNode
  alias Seed.Token
  alias Seed.TokenStream
  alias Seed.Vocabulary

  @eof Token.eof()

  @type t :: %__MODULE__{
          atn: ATN.t(),
          input: TokenStream.t(),
          vocabulary: Vocabulary.t(),
          state: integer(),
          frames: [ParserRuleContext.t()],
          precedence_stack: [integer()],
          parent_context_stack: [integer()],
          diagnostics: [Diagnostic.t()]
        }

  @enforce_keys [:atn, :input]
  defstruct atn: nil,
            input: nil,
            vocabulary: nil,
            state: -1,
            frames: [],
            precedence_stack: [],
            parent_context_stack: [],
            diagnostics: []

  defmodule Error do
    @moduledoc """
    Raised on an unrecoverable parse error.

    Carries every `Seed.Diagnostic` accumulated so far (recovered errors
    plus the final, unrecoverable one), so the public boundary can report
    them all.
    """
    defexception [:diagnostics]

    @impl true
    def message(%__MODULE__{diagnostics: [first | _]}), do: first.message
  end

  @doc """
  Builds a parser over `atn` reading `input`.

  `vocabulary` supplies token names for diagnostics; it defaults to an empty
  vocabulary, in which case messages fall back to numeric token types.
  """
  @spec new(ATN.t(), TokenStream.t(), Vocabulary.t()) :: t()
  def new(%ATN{} = atn, %TokenStream{} = input, vocabulary \\ Vocabulary.empty()) do
    %__MODULE__{atn: atn, input: input, vocabulary: vocabulary}
  end

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
    wrapper =
      rule_index |> ParserRuleContext.new(invoking_state) |> ParserRuleContext.add_child(previous)

    %{parser | frames: [wrapper | rest]}
  end

  @doc """
  Matches the current token against `token_type` and consumes it.

  On a mismatch it attempts single-token deletion: if the *next* token is
  the expected one, the current token is reported as extraneous and dropped,
  and parsing continues. Otherwise the error is unrecoverable and is raised
  with every diagnostic accumulated so far.
  """
  @spec match(t(), integer()) :: t()
  def match(%__MODULE__{} = parser, token_type) do
    token = TokenStream.lt(parser.input, 1)

    cond do
      token.type == token_type ->
        consume(parser)

      TokenStream.la(parser.input, 2) == token_type ->
        delete_extraneous_token(parser, token)

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

  # Reports the current token as extraneous, drops it, and matches the
  # expected token that follows.
  defp delete_extraneous_token(parser, token) do
    diagnostic =
      Diagnostic.error(:extraneous_input, "extraneous input #{describe(token)}",
        line: token.line,
        column: token.column
      )

    parser
    |> add_diagnostic(diagnostic)
    |> Map.update!(:input, &TokenStream.consume/1)
    |> consume()
  end

  defp token_mismatch(parser, token, token_type) do
    Diagnostic.error(
      :token_mismatch,
      "mismatched input #{describe(token)}, expected #{Vocabulary.display_name(parser.vocabulary, token_type)}",
      line: token.line,
      column: token.column
    )
  end

  # Raises with the accumulated diagnostics plus the unrecoverable one.
  @spec fail(t(), Diagnostic.t()) :: no_return()
  defp fail(parser, diagnostic) do
    raise Error, diagnostics: parser.diagnostics ++ [diagnostic]
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
    %{parser | state: completed.invoking_state, frames: rest} |> add_child(completed)
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

    {result, add_child(parser, result)}
  end

  # Appends a child to the current frame; a no-op when there is no frame
  # (the root rule has no parent to reparent into).
  defp add_child(%__MODULE__{frames: []} = parser, _child), do: parser

  defp add_child(%__MODULE__{frames: [ctx | rest]} = parser, child) do
    %{parser | frames: [ParserRuleContext.add_child(ctx, child) | rest]}
  end
end
