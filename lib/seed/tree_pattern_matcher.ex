defmodule Seed.TreePatternMatcher do
  @moduledoc """
  Matches parse trees against *tree patterns*, after the reference
  `org.antlr.v4.runtime.tree.pattern.ParseTreePatternMatcher`.

  A pattern is a string in the concrete syntax of the grammar with tagged
  holes — `<ID> = <expr> ;` — where an upper-case tag (`<ID>`) stands for any
  token of that type and a lower-case tag (`<expr>`) for any subtree of that
  rule. A tag may carry a label, `<lhs:ID>`, binding the matched node under
  both the tag name and the label.

      lexer  = Seed.Interp.load!("ExprLexer.interp")
      parser = Seed.Interp.load!("Expr.interp")
      m      = Seed.TreePatternMatcher.new(lexer, parser)

      {:ok, tree} = Seed.parse(parser, lexer, "x = 3;", 0)
      match = Seed.TreePatternMatcher.match(m, tree, "<ID> = <expr>;", stat_rule_index)
      Seed.ParseTreeMatch.succeeded?(match)        #=> true
      Seed.ParseTreeMatch.get(match, "ID")         #=> the `x` terminal

  Compilation parses the pattern with the grammar's *bypass-alternatives* ATN
  (`Seed.ATN.BypassAlts`), so a `<rule>` tag is consumed as a single imaginary
  token standing for the whole subtree. Matching is then a structural walk of
  the subject tree against the pattern tree, binding tags to nodes.
  """

  alias Seed.ATN.BypassAlts
  alias Seed.ErrorNode
  alias Seed.Grammar
  alias Seed.ParserInterpreter
  alias Seed.ParserRuleContext
  alias Seed.ParseTreeMatch
  alias Seed.TerminalNode
  alias Seed.Token
  alias Seed.TokenStream
  alias Seed.TreePattern
  alias Seed.XPath

  @start "<"
  @stop ">"
  @escape "\\"

  @type t :: %__MODULE__{
          lexer: Grammar.t(),
          parser: Grammar.t(),
          bypass: Grammar.t()
        }

  @enforce_keys [:lexer, :parser, :bypass]
  defstruct [:lexer, :parser, :bypass]

  @doc """
  Builds a matcher from the `lexer` and `parser` grammars.

  The parser's bypass-alternatives ATN is computed once here and reused for
  every `compile/3`.
  """
  @spec new(Grammar.t(), Grammar.t()) :: t()
  def new(%Grammar{} = lexer, %Grammar{} = parser) do
    %__MODULE__{lexer: lexer, parser: parser, bypass: %{parser | atn: BypassAlts.add(parser.atn)}}
  end

  @doc """
  Compiles `pattern` as `rule_index` into a reusable `Seed.TreePattern`.

  Raises `ArgumentError` for an unknown tag, a malformed pattern (the pattern
  does not parse as the rule), or a pattern the rule does not fully consume.
  """
  @spec compile(t(), String.t(), non_neg_integer()) :: TreePattern.t()
  def compile(%__MODULE__{} = matcher, pattern, rule_index) when is_binary(pattern) do
    tokens = tokenize(matcher, pattern)
    visible = Enum.count(tokens, &(&1.channel == Token.default_channel()))
    stream = TokenStream.new(tokens ++ [Token.eof_token()])

    tree =
      case ParserInterpreter.parse(matcher.bypass, stream, rule_index, bail: true) do
        {:ok, tree} ->
          tree

        {:error, [diagnostic | _]} ->
          raise ArgumentError,
                "pattern does not parse as rule #{rule_index}: #{diagnostic.message} " <>
                  "(pattern: #{inspect(pattern)})"
      end

    if count_terminals(tree) != visible do
      raise ArgumentError,
            "rule #{rule_index} does not consume the whole pattern: #{inspect(pattern)}"
    end

    %TreePattern{matcher: matcher, pattern: pattern, rule_index: rule_index, tree: tree}
  end

  @doc "Matches `tree` against a compiled pattern, returning a `Seed.ParseTreeMatch`."
  @spec match(TreePattern.t(), ParseTreeMatch.tree_node()) :: ParseTreeMatch.t()
  def match(%TreePattern{} = pattern, tree) do
    {mismatched, labels} = match_impl(tree, pattern.tree, %{})
    %ParseTreeMatch{tree: tree, pattern: pattern, labels: labels, mismatched_node: mismatched}
  end

  @doc "Compiles `pattern` as `rule_index` and matches `tree` against it."
  @spec match(t(), ParseTreeMatch.tree_node(), String.t(), non_neg_integer()) ::
          ParseTreeMatch.t()
  def match(%__MODULE__{} = matcher, tree, pattern, rule_index) when is_binary(pattern) do
    match(compile(matcher, pattern, rule_index), tree)
  end

  @doc "Returns whether `tree` matches a compiled pattern."
  @spec matches?(TreePattern.t(), ParseTreeMatch.tree_node()) :: boolean()
  def matches?(%TreePattern{} = pattern, tree) do
    {mismatched, _labels} = match_impl(tree, pattern.tree, %{})
    mismatched == nil
  end

  @doc "Compiles `pattern` as `rule_index` and returns whether `tree` matches it."
  @spec matches?(t(), ParseTreeMatch.tree_node(), String.t(), non_neg_integer()) :: boolean()
  def matches?(%__MODULE__{} = matcher, tree, pattern, rule_index) when is_binary(pattern) do
    matches?(compile(matcher, pattern, rule_index), tree)
  end

  @doc """
  Returns a successful `Seed.ParseTreeMatch` for every node in `tree` selected
  by the XPath `xpath` that matches the compiled `pattern`.
  """
  @spec find_all(TreePattern.t(), ParseTreeMatch.tree_node(), String.t()) :: [ParseTreeMatch.t()]
  def find_all(%TreePattern{matcher: matcher} = pattern, tree, xpath) when is_binary(xpath) do
    tree
    |> XPath.find(xpath, matcher.parser)
    |> Enum.map(&match(pattern, &1))
    |> Enum.filter(&ParseTreeMatch.succeeded?/1)
  end

  # --- Structural match (matchImpl) ---------------------------------------

  # Both leaves: a token tag binds; otherwise the token types and text must be
  # equal. An `ErrorNode` in the subject is treated as a terminal, as in the
  # reference (where it is a `TerminalNode` subclass).
  defp match_impl(tree, pattern, labels)
       when is_struct(tree, TerminalNode) or is_struct(tree, ErrorNode) do
    case pattern do
      %TerminalNode{symbol: %Token{} = ps} -> match_terminal(tree, tree.symbol, ps, labels)
      _ -> {tree, labels}
    end
  end

  defp match_impl(%ParserRuleContext{} = r1, %ParserRuleContext{} = r2, labels) do
    case rule_tag(r2) do
      {:rule, name, label} -> match_rule_tag(r1, r2, name, label, labels)
      nil -> match_rule_children(r1, r2, labels)
    end
  end

  # Mismatched node kinds (a rule against a terminal, or vice versa).
  defp match_impl(tree, _pattern, labels), do: {tree, labels}

  defp match_terminal(tree, %Token{type: type} = s1, %Token{type: type} = s2, labels) do
    case s2.tag do
      {:token, name, label} -> {nil, bind_tag(labels, name, label, tree)}
      _ -> if Token.text(s1) == Token.text(s2), do: {nil, labels}, else: {tree, labels}
    end
  end

  defp match_terminal(tree, _s1, _s2, labels), do: {tree, labels}

  defp match_rule_tag(r1, r2, name, label, labels) do
    if r1.rule_index == r2.rule_index do
      {nil, bind_tag(labels, name, label, r1)}
    else
      {r1, labels}
    end
  end

  # No rule-index check here, mirroring the reference: positional structure
  # (child count and recursive matches) decides equality.
  defp match_rule_children(r1, r2, labels) do
    if length(r1.children) != length(r2.children) do
      {r1, labels}
    else
      match_children(r1.children, r2.children, labels)
    end
  end

  defp match_children([], [], labels), do: {nil, labels}

  defp match_children([c1 | rest1], [c2 | rest2], labels) do
    case match_impl(c1, c2, labels) do
      {nil, labels} -> match_children(rest1, rest2, labels)
      {mismatched, labels} -> {mismatched, labels}
    end
  end

  # `(expr <expr>)` — a rule context whose sole child is a rule-tag terminal.
  defp rule_tag(%ParserRuleContext{
         children: [%TerminalNode{symbol: %Token{tag: {:rule, _, _} = tag}}]
       }),
       do: tag

  defp rule_tag(_node), do: nil

  defp bind_tag(labels, name, label, node) do
    labels = bind(labels, name, node)
    if label, do: bind(labels, label, node), else: labels
  end

  defp bind(labels, key, node), do: Map.update(labels, key, [node], &(&1 ++ [node]))

  # --- Tokenizing the pattern (split + tokenize) --------------------------

  defp tokenize(matcher, pattern) do
    pattern
    |> split()
    |> Enum.flat_map(fn
      {:text, text} -> lex_text(matcher, text)
      {:tag, label, name} -> [tag_token(matcher, name, label, pattern)]
    end)
  end

  defp lex_text(matcher, text) do
    case Seed.tokenize(matcher.lexer, text) do
      {:ok, tokens} ->
        Enum.reject(tokens, &Token.eof?/1)

      {:error, [diagnostic | _]} ->
        raise ArgumentError, "cannot lex pattern text #{inspect(text)}: #{diagnostic.message}"
    end
  end

  defp tag_token(matcher, name, label, pattern) do
    cond do
      upper_first?(name) -> token_tag(matcher, name, label, pattern)
      lower_first?(name) -> rule_tag_token(matcher, name, label, pattern)
      true -> raise ArgumentError, "invalid tag #{inspect(name)} in pattern: #{inspect(pattern)}"
    end
  end

  defp token_tag(matcher, name, label, pattern) do
    type = token_type!(matcher.parser, name, pattern)
    %Token{type: type, text: tag_text(name, label), tag: {:token, name, label}}
  end

  defp rule_tag_token(matcher, name, label, pattern) do
    rule_index = rule_index!(matcher.parser, name, pattern)
    type = Enum.at(matcher.bypass.atn.rule_to_token_type, rule_index)
    %Token{type: type, text: tag_text(name, label), tag: {:rule, name, label}}
  end

  defp tag_text(name, nil), do: @start <> name <> @stop
  defp tag_text(name, label), do: @start <> label <> ":" <> name <> @stop

  defp upper_first?(name), do: String.match?(String.first(name) || "", ~r/^\p{Lu}$/u)
  defp lower_first?(name), do: String.match?(String.first(name) || "", ~r/^\p{Ll}$/u)

  defp token_type!(%Grammar{vocabulary: vocab}, name, pattern) do
    case Enum.find(vocab.symbolic_names, fn {_type, value} -> value == name end) do
      {type, _value} -> type
      nil -> raise ArgumentError, "unknown token #{name} in pattern: #{inspect(pattern)}"
    end
  end

  defp rule_index!(%Grammar{rule_names: rules}, name, pattern) do
    case Enum.find_index(rules, &(&1 == name)) do
      nil -> raise ArgumentError, "unknown rule #{name} in pattern: #{inspect(pattern)}"
      index -> index
    end
  end

  # Split a pattern into alternating text and tag chunks. Escaped delimiters
  # (`\<`, `\>`) are literal text; the escape character is stripped from text
  # chunks (mirroring the reference's final unescape pass).
  defp split(pattern), do: scan(String.graphemes(pattern), [], "")

  defp scan([], chunks, buf), do: Enum.reverse(flush_text(chunks, buf))

  defp scan([@escape, c | rest], chunks, buf) when c in [@start, @stop],
    do: scan(rest, chunks, buf <> c)

  defp scan([@escape | rest], chunks, buf), do: scan(rest, chunks, buf)

  defp scan([@start | rest], chunks, buf) do
    {content, rest} = read_tag(rest, "")
    scan(rest, [to_tag(content) | flush_text(chunks, buf)], "")
  end

  defp scan([@stop | _rest], _chunks, _buf) do
    raise ArgumentError, "missing start tag before #{inspect(@stop)} in pattern"
  end

  defp scan([c | rest], chunks, buf), do: scan(rest, chunks, buf <> c)

  defp read_tag([], _acc), do: raise(ArgumentError, "unterminated tag in pattern")

  defp read_tag([@escape, c | rest], acc) when c in [@start, @stop],
    do: read_tag(rest, acc <> @escape <> c)

  defp read_tag([@stop | rest], acc), do: {acc, rest}
  defp read_tag([c | rest], acc), do: read_tag(rest, acc <> c)

  defp to_tag(content) do
    case String.split(content, ":", parts: 2) do
      [name] -> {:tag, nil, name}
      [label, name] -> {:tag, label, name}
    end
  end

  defp flush_text(chunks, ""), do: chunks
  defp flush_text(chunks, buf), do: [{:text, buf} | chunks]

  # --- Misc ---------------------------------------------------------------

  defp count_terminals(%ParserRuleContext{children: children}),
    do: Enum.sum_by(children, &count_terminals/1)

  defp count_terminals(_leaf), do: 1
end
