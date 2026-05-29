defmodule Seed.Lexer do
  @moduledoc """
  Turns a character stream into tokens by driving the lexer ATN simulator.

  The lexer is an immutable value: `next_token/1` returns the next token
  and the advanced lexer, and `tokenize/1` collects every token (ending
  with EOF). It implements the reference `Lexer.nextToken` driver loop:
  match a token with `Seed.LexerATNSimulator`, run the accepted rule's
  lexer commands, and emit a token — unless a command says to `skip` it or
  gather `more` input first.

  Lexer commands are applied by interpreting the accepted token's
  `Seed.ATN.LexerActionExecutor`: `skip`, `more`, `type`, `channel`,
  `mode`, `pushMode`, and `popMode`. Custom embedded actions need a
  generated recognizer to run and are currently no-ops.
  """

  alias Seed.ATN
  alias Seed.ATN.{LexerAction, LexerActionExecutor}
  alias Seed.CharStream
  alias Seed.LexerATNSimulator
  alias Seed.Token

  @skip -3
  @more -2
  @invalid_type Token.invalid_type()
  @default_channel Token.default_channel()
  @default_mode 0
  @eof Token.eof()

  @type t :: %__MODULE__{
          atn: ATN.t(),
          input: CharStream.t(),
          mode: non_neg_integer(),
          mode_stack: [non_neg_integer()],
          line: pos_integer(),
          column: non_neg_integer(),
          hit_eof: boolean(),
          channel: integer(),
          type: integer(),
          token_start_index: non_neg_integer(),
          token_start_line: pos_integer(),
          token_start_column: non_neg_integer()
        }

  @enforce_keys [:atn, :input]
  defstruct atn: nil,
            input: nil,
            mode: 0,
            mode_stack: [],
            line: 1,
            column: 0,
            hit_eof: false,
            channel: 0,
            type: 0,
            token_start_index: 0,
            token_start_line: 1,
            token_start_column: 0

  defmodule Error do
    @moduledoc "Raised when the lexer cannot match any token at a position."
    defexception [:message]
  end

  @doc "Builds a lexer over `atn` reading the character stream `input`."
  @spec new(ATN.t(), CharStream.t()) :: t()
  def new(%ATN{} = atn, input), do: %__MODULE__{atn: atn, input: input}

  @doc """
  Returns the next token and the advanced lexer.

  Once end of input is reached, returns the EOF token on every call.
  """
  @spec next_token(t()) :: {Token.t(), t()}
  def next_token(%__MODULE__{hit_eof: true} = lexer), do: {emit_eof(lexer), lexer}

  def next_token(%__MODULE__{} = lexer) do
    lexer
    |> reset_token_start()
    |> match_token()
  end

  @doc """
  Tokenizes the entire input, returning all tokens including the final EOF.
  """
  @spec tokenize(t()) :: [Token.t()]
  def tokenize(%__MODULE__{} = lexer) do
    {token, lexer} = next_token(lexer)

    if token.type == @eof do
      [token]
    else
      [token | tokenize(lexer)]
    end
  end

  defp reset_token_start(lexer) do
    %{
      lexer
      | channel: @default_channel,
        type: @invalid_type,
        token_start_index: CharStream.index(lexer.input),
        token_start_line: lexer.line,
        token_start_column: lexer.column
    }
  end

  defp match_token(lexer) do
    lexer = %{lexer | type: @invalid_type}

    case LexerATNSimulator.match(lexer.atn, lexer.input, lexer.mode, lexer.line, lexer.column) do
      {:eof, input, line, column} ->
        lexer = %{lexer | input: input, line: line, column: column, hit_eof: true}
        {emit_eof(lexer), lexer}

      {:no_viable, _input, start_index, _line, _column} ->
        raise Error, message: "no viable alternative at input index #{start_index}"

      {:ok, token_type, executor, input, line, column} ->
        finish_match(lexer, token_type, executor, input, line, column)
    end
  end

  defp finish_match(lexer, token_type, executor, input, line, column) do
    lexer = %{lexer | input: input, line: line, column: column}
    lexer = apply_executor(lexer, executor)
    lexer = if CharStream.la(input, 1) == @eof, do: %{lexer | hit_eof: true}, else: lexer
    lexer = if lexer.type == @invalid_type, do: %{lexer | type: token_type}, else: lexer

    cond do
      lexer.type == @skip -> next_token(lexer)
      lexer.type == @more -> match_token(lexer)
      true -> {emit(lexer), lexer}
    end
  end

  defp apply_executor(lexer, executor) do
    Enum.reduce(LexerActionExecutor.actions(executor), lexer, &apply_action/2)
  end

  defp apply_action(%LexerAction{type: :skip}, lexer), do: %{lexer | type: @skip}
  defp apply_action(%LexerAction{type: :more}, lexer), do: %{lexer | type: @more}
  defp apply_action(%LexerAction{type: :type, data1: type}, lexer), do: %{lexer | type: type}

  defp apply_action(%LexerAction{type: :channel, data1: channel}, lexer),
    do: %{lexer | channel: channel}

  defp apply_action(%LexerAction{type: :mode, data1: mode}, lexer), do: %{lexer | mode: mode}

  defp apply_action(%LexerAction{type: :push_mode, data1: mode}, lexer) do
    %{lexer | mode_stack: [lexer.mode | lexer.mode_stack], mode: mode}
  end

  defp apply_action(%LexerAction{type: :pop_mode}, lexer) do
    case lexer.mode_stack do
      [top | rest] -> %{lexer | mode: top, mode_stack: rest}
      [] -> %{lexer | mode: @default_mode}
    end
  end

  defp apply_action(%LexerAction{type: :custom}, lexer), do: lexer

  defp emit(lexer) do
    stop = CharStream.index(lexer.input) - 1

    %Token{
      type: lexer.type,
      text: CharStream.text(lexer.input, lexer.token_start_index, stop),
      line: lexer.token_start_line,
      column: lexer.token_start_column,
      start: lexer.token_start_index,
      stop: stop,
      channel: lexer.channel
    }
  end

  defp emit_eof(lexer) do
    index = CharStream.index(lexer.input)

    %Token{
      # ANTLR's getText returns the "<EOF>" sentinel for the EOF token,
      # whose [start, stop] interval is empty.
      type: @eof,
      text: "<EOF>",
      line: lexer.line,
      column: lexer.column,
      start: index,
      stop: index - 1,
      channel: @default_channel
    }
  end
end
