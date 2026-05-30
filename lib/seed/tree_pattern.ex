defmodule Seed.TreePattern do
  @moduledoc """
  A compiled tree pattern, after the reference
  `org.antlr.v4.runtime.tree.pattern.ParseTreePattern`.

  Produced by `Seed.TreePatternMatcher.compile/3`, it holds the pattern's
  parse `tree` (with `<tag>` placeholders), the originating `pattern` string,
  the `rule_index` it was compiled as, and the `matcher` that built it (so it
  can match and run XPath without re-supplying the grammars).
  """

  alias Seed.ErrorNode
  alias Seed.ParserRuleContext
  alias Seed.TerminalNode

  @type tree_node :: ParserRuleContext.t() | TerminalNode.t() | ErrorNode.t()

  @type t :: %__MODULE__{
          matcher: Seed.TreePatternMatcher.t(),
          pattern: String.t(),
          rule_index: non_neg_integer(),
          tree: tree_node()
        }

  @enforce_keys [:matcher, :pattern, :rule_index, :tree]
  defstruct [:matcher, :pattern, :rule_index, :tree]
end
