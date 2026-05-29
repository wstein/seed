defmodule Seed do
  @moduledoc """
  Seed is an ANTLR4 parser runtime for the BEAM, written in idiomatic Elixir.

  It lexes and parses input directly from a grammar's serialized ATN — no
  code generation. Load a grammar from its ANTLR `.interp` file with
  `Seed.Interp.load!/1`, then use the convenience entry points here:

      lexer = Seed.Interp.load!("ExprLexer.interp")
      parser = Seed.Interp.load!("Expr.interp")
      {:ok, tree} = Seed.parse(parser, lexer, "x = 1 + 2;", 0)

  Both `parse/4` and `tokenize/2` return `{:ok, result} | {:error,
  [Seed.Diagnostic.t()]}`. For a compile-time alternative that bakes the
  grammar into a module with named entry points, see `Seed.Generated`. See
  the architecture documentation under `docs/` for the design and the
  lower-level building blocks (`Seed.Lexer`, `Seed.ParserInterpreter`,
  `Seed.Trees`, …).
  """

  alias Seed.CharStream
  alias Seed.Diagnostic
  alias Seed.Grammar
  alias Seed.Lexer
  alias Seed.ParserInterpreter
  alias Seed.ParserRuleContext
  alias Seed.Token
  alias Seed.TokenStream

  @version Mix.Project.config()[:version]

  @doc """
  Returns the Seed version string.

      iex> Seed.version() |> is_binary()
      true
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Tokenizes `input` with `lexer_grammar`.

  Returns `{:ok, tokens}` (ending with the EOF token) or
  `{:error, [Seed.Diagnostic.t()]}`.

  Options:

    * `:sempred` — a `t:Seed.LexerATNSimulator.sempred/0` evaluating lexer
      semantic predicates `{...}?`; defaults to treating every predicate as
      satisfied.
  """
  @spec tokenize(Grammar.t(), binary(), keyword()) ::
          {:ok, [Token.t()]} | {:error, [Diagnostic.t()]}
  def tokenize(%Grammar{atn: atn}, input, opts \\ []) when is_binary(input) do
    atn |> Lexer.new(CharStream.new(input), opts[:sempred]) |> Lexer.tokenize()
  end

  @doc """
  Parses `input` end to end: lex it with `lexer_grammar`, then parse from
  `start_rule_index` with `parser_grammar`.

  Returns `{:ok, tree}` for well-formed input. A lexing failure returns
  `{:error, diagnostics}`; a parsing failure returns `{:error, diagnostics,
  tree}`, the partially recovered tree (with `Seed.ErrorNode` leaves) being
  available since the parser always recovers.

  `opts` are forwarded to `Seed.ParserInterpreter.parse/4` — notably
  `:sempred`, a `t:Seed.Parser.sempred/0` evaluating grammar semantic
  predicates `{...}?`.
  """
  @spec parse(Grammar.t(), Grammar.t(), binary(), non_neg_integer(), keyword()) ::
          {:ok, ParserRuleContext.t()}
          | {:error, [Diagnostic.t()]}
          | {:error, [Diagnostic.t()], ParserRuleContext.t()}
  def parse(
        %Grammar{} = parser_grammar,
        %Grammar{atn: lexer_atn},
        input,
        start_rule_index,
        opts \\ []
      )
      when is_binary(input) do
    with {:ok, stream} <-
           lexer_atn |> Lexer.new(CharStream.new(input)) |> TokenStream.from_lexer() do
      ParserInterpreter.parse(parser_grammar, stream, start_rule_index, opts)
    end
  end
end
