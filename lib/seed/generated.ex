defmodule Seed.Generated do
  @moduledoc """
  Generates a parser module from ANTLR `.interp` artifacts — the Elixir
  target.

  Seed can parse a grammar straight from its serialized ATN at run time
  (`Seed.Interp` + `Seed.ParserInterpreter`). This module is the ergonomic,
  zero-runtime-load alternative: `use Seed.Generated` reads the lexer and
  parser `.interp` files *at compile time*, bakes the deserialized grammars
  into the module, and emits named entry points backed by the same runtime.

      defmodule MyGrammar do
        use Seed.Generated,
          parser: "grammars/Expr.interp",
          lexer: "grammars/ExprLexer.interp"
      end

      {:ok, tree} = MyGrammar.parse("x = 1 + 2 ;")
      {:ok, tree} = MyGrammar.parse_expr("1 + 2")

  Paths are resolved relative to the compiling project's working directory
  and registered as `@external_resource`, so the module recompiles when an
  `.interp` file changes.

  The generated module exposes:

    * `parser_grammar/0`, `lexer_grammar/0` — the baked `Seed.Grammar`s;
    * `rule_names/0`, `vocabulary/0` — grammar metadata;
    * `tokenize/1` — lex a string with the baked lexer;
    * `parse/1` — parse from the start rule (index 0);
    * `parse/2` — parse from a rule given by name (atom/string) or index;
    * `parse_<rule>/1` — one entry point per parser rule.

  Each parse/tokenize function returns `{:ok, result} | {:error,
  [Seed.Diagnostic.t()]}`, exactly like the `Seed` facade it delegates to.
  """

  alias Seed.Interp

  @doc false
  defmacro __using__(opts) do
    parser_path = Keyword.fetch!(opts, :parser)
    lexer_path = Keyword.fetch!(opts, :lexer)

    parser_grammar = Interp.load!(parser_path)
    lexer_grammar = Interp.load!(lexer_path)
    rule_index = parser_grammar.rule_names |> Enum.with_index() |> Map.new()

    rule_functions =
      for {name, index} <- rule_index do
        function = String.to_atom("parse_" <> name)

        quote do
          @doc "Parses `input` beginning at the `#{unquote(name)}` rule."
          @spec unquote(function)(binary()) ::
                  {:ok, Seed.ParserRuleContext.t()} | {:error, [Seed.Diagnostic.t()]}
          def unquote(function)(input) when is_binary(input), do: parse(input, unquote(index))
        end
      end

    quote do
      @external_resource unquote(parser_path)
      @external_resource unquote(lexer_path)

      @parser_grammar unquote(Macro.escape(parser_grammar))
      @lexer_grammar unquote(Macro.escape(lexer_grammar))
      @rule_index unquote(Macro.escape(rule_index))

      @doc "The baked parser grammar (ATN, vocabulary, and names)."
      @spec parser_grammar() :: Seed.Grammar.t()
      def parser_grammar, do: @parser_grammar

      @doc "The baked lexer grammar."
      @spec lexer_grammar() :: Seed.Grammar.t()
      def lexer_grammar, do: @lexer_grammar

      @doc "The parser rule names, in rule-index order."
      @spec rule_names() :: [String.t()]
      def rule_names, do: parser_grammar().rule_names

      @doc "The token vocabulary."
      @spec vocabulary() :: Seed.Vocabulary.t()
      def vocabulary, do: parser_grammar().vocabulary

      @doc "Tokenizes `input` with the baked lexer."
      @spec tokenize(binary()) ::
              {:ok, [Seed.Token.t()]} | {:error, [Seed.Diagnostic.t()]}
      def tokenize(input) when is_binary(input), do: Seed.tokenize(lexer_grammar(), input)

      @doc "Parses `input` beginning at the start rule (index 0)."
      @spec parse(binary()) ::
              {:ok, Seed.ParserRuleContext.t()} | {:error, [Seed.Diagnostic.t()]}
      def parse(input) when is_binary(input), do: parse(input, 0)

      @doc """
      Parses `input` beginning at `rule` — a rule name (atom or string) or a
      0-based rule index. Raises `ArgumentError` for an unknown rule name.
      """
      @spec parse(binary(), non_neg_integer() | atom() | String.t()) ::
              {:ok, Seed.ParserRuleContext.t()} | {:error, [Seed.Diagnostic.t()]}
      def parse(input, rule) when is_binary(input) and is_integer(rule) do
        Seed.parse(parser_grammar(), lexer_grammar(), input, rule, sempred: &sempred/3)
      end

      def parse(input, rule) when is_binary(input) and (is_atom(rule) or is_binary(rule)) do
        case Map.fetch(@rule_index, to_string(rule)) do
          {:ok, index} ->
            parse(input, index)

          :error ->
            raise ArgumentError,
                  "unknown rule #{inspect(rule)}; known rules: #{inspect(rule_names())}"
        end
      end

      @doc """
      Evaluates a grammar semantic predicate `{...}?`.

      Override this to make predicated alternatives behave correctly; the
      default treats every predicate as satisfied. The arguments are the
      predicate's rule index, its per-rule predicate index, and the current
      rule context.
      """
      @spec sempred(integer(), integer(), Seed.ParserRuleContext.t()) :: boolean()
      def sempred(_rule_index, _pred_index, _context), do: true

      defoverridable sempred: 3

      unquote(rule_functions)
    end
  end
end
