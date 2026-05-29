defmodule Seed.XPath do
  @moduledoc """
  Locates parse-tree nodes with an XPath-like query, after the reference
  `org.antlr.v4.runtime.tree.xpath.XPath`.

  A query is a sequence of steps, each introduced by `/` (a direct child) or
  `//` (a descendant at any depth), and the whole query is anchored at the
  tree passed to `find/3`:

    * a *rule name* (e.g. `expr`) matches rule contexts of that rule;
    * a *token name* (e.g. `ID`) or *literal* (e.g. `'='`) matches terminals
      (and error nodes) of that token;
    * `*` matches any node; and
    * a leading `!` inverts a step (e.g. `/prog/!stat` — children of `prog`
      that are not `stat`).

  Names are resolved against the grammar (rule names and vocabulary), so an
  unknown name raises `ArgumentError`.

      Seed.XPath.find(tree, "//ID", grammar)        # every ID terminal
      Seed.XPath.find(tree, "/prog/stat", grammar)  # stat children of the root
      Seed.XPath.find(tree, "//expr/*", grammar)    # children of every expr

  Returns the matching nodes in document order, deduplicated.
  """

  alias Seed.ErrorNode
  alias Seed.Grammar
  alias Seed.ParserRuleContext
  alias Seed.TerminalNode

  @type node_t :: ParserRuleContext.t() | TerminalNode.t() | ErrorNode.t()

  @doc "Returns the nodes in `tree` matching `path`, resolved against `grammar`."
  @spec find(node_t(), String.t(), Grammar.t()) :: [node_t()]
  def find(tree, path, %Grammar{} = grammar) when is_binary(path) do
    path
    |> parse(grammar)
    |> Enum.reduce([{:root, tree}], fn step, work ->
      work |> Enum.flat_map(&eval_step(step, &1)) |> Enum.uniq()
    end)
  end

  # --- Evaluation ---------------------------------------------------------

  defp eval_step(%{scope: scope, invert: invert, test: test}, node) do
    node
    |> candidates(scope)
    |> Enum.filter(fn candidate -> matches?(test, candidate) != invert end)
  end

  # The synthetic root's only child is the tree, so `/x` anchors on the tree
  # itself and `//x` searches the whole tree.
  defp candidates({:root, tree}, :children), do: [tree]
  defp candidates({:root, tree}, :descendants), do: descendants(tree)
  defp candidates(node, :children), do: children(node)
  defp candidates(node, :descendants), do: descendants(node)

  defp children(%ParserRuleContext{children: children}), do: children
  defp children(_leaf), do: []

  defp descendants(node), do: [node | Enum.flat_map(children(node), &descendants/1)]

  defp matches?(:wildcard, _node), do: true
  defp matches?({:rule, index}, %ParserRuleContext{rule_index: index}), do: true
  defp matches?({:token, type}, %TerminalNode{symbol: %{type: type}}), do: true
  defp matches?({:token, type}, %ErrorNode{symbol: %{type: type}}), do: true
  defp matches?(_test, _node), do: false

  # --- Parsing ------------------------------------------------------------

  defp parse(path, grammar), do: parse(path, grammar, [])

  defp parse("", _grammar, acc), do: Enum.reverse(acc)

  defp parse("//" <> rest, grammar, acc) do
    {segment, rest} = take_segment(rest)
    parse(rest, grammar, [step(:descendants, segment, grammar) | acc])
  end

  defp parse("/" <> rest, grammar, acc) do
    {segment, rest} = take_segment(rest)
    parse(rest, grammar, [step(:children, segment, grammar) | acc])
  end

  defp parse(other, _grammar, _acc) do
    raise ArgumentError, "XPath must start with '/' or '//', got: #{inspect(other)}"
  end

  defp take_segment(str) do
    case :binary.match(str, "/") do
      {pos, _len} -> {binary_part(str, 0, pos), binary_part(str, pos, byte_size(str) - pos)}
      :nomatch -> {str, ""}
    end
  end

  defp step(_scope, "", _grammar), do: raise(ArgumentError, "empty XPath segment")

  defp step(scope, "!" <> name, grammar) do
    %{scope: scope, invert: true, test: classify(name, grammar)}
  end

  defp step(scope, name, grammar) do
    %{scope: scope, invert: false, test: classify(name, grammar)}
  end

  defp classify("*", _grammar), do: :wildcard
  defp classify("'" <> _rest = literal, grammar), do: {:token, resolve_literal!(grammar, literal)}

  defp classify(name, grammar) do
    if String.match?(name, ~r/^[A-Z]/) do
      {:token, resolve_symbolic!(grammar, name)}
    else
      {:rule, resolve_rule!(grammar, name)}
    end
  end

  defp resolve_rule!(%Grammar{rule_names: rules}, name) do
    case Enum.find_index(rules, &(&1 == name)) do
      nil -> raise ArgumentError, "no rule named #{name} in the grammar"
      index -> index
    end
  end

  defp resolve_symbolic!(%Grammar{vocabulary: vocab}, name) do
    find_token(vocab.symbolic_names, name, "no token named #{name} in the grammar")
  end

  defp resolve_literal!(%Grammar{vocabulary: vocab}, literal) do
    find_token(vocab.literal_names, literal, "no literal #{literal} in the grammar")
  end

  defp find_token(names, name, error) do
    case Enum.find(names, fn {_type, value} -> value == name end) do
      {type, _value} -> type
      nil -> raise ArgumentError, error
    end
  end
end
