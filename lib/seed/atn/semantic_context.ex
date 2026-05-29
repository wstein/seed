defmodule Seed.ATN.SemanticContext do
  @moduledoc """
  The predicates that guard an ATN configuration.

  A semantic context is one of:

    * `:none` — no predicate (always satisfied);
    * `%Predicate{}` — a grammar semantic predicate `{...}?`, evaluated by a
      recognizer;
    * `%PrecedencePredicate{}` — the precedence guard of a left-recursive
      rule; or
    * `%And{}` / `%Or{}` — boolean combinations.

  Evaluation is parameterised by a callback so the runtime stays decoupled
  from generated recognizer code: `eval/2` and `eval_precedence/2` take a
  function that decides a single `%Predicate{}` or `%PrecedencePredicate{}`.

  `eval_precedence/2` powers the parser's left-recursion precedence filter:
  a precedence predicate simplifies to `:none` when satisfied and to `nil`
  (filtered out) when not.
  """

  defmodule Predicate do
    @moduledoc "A grammar semantic predicate `{...}?`."
    @type t :: %__MODULE__{rule_index: integer(), pred_index: integer(), ctx_dependent: boolean()}
    @enforce_keys [:rule_index, :pred_index, :ctx_dependent]
    defstruct [:rule_index, :pred_index, :ctx_dependent]
  end

  defmodule PrecedencePredicate do
    @moduledoc "The precedence guard of a left-recursive rule."
    @type t :: %__MODULE__{precedence: integer()}
    @enforce_keys [:precedence]
    defstruct [:precedence]
  end

  defmodule And do
    @moduledoc "Conjunction of semantic contexts."
    @type t :: %__MODULE__{operands: [Seed.ATN.SemanticContext.t()]}
    @enforce_keys [:operands]
    defstruct [:operands]
  end

  defmodule Or do
    @moduledoc "Disjunction of semantic contexts."
    @type t :: %__MODULE__{operands: [Seed.ATN.SemanticContext.t()]}
    @enforce_keys [:operands]
    defstruct [:operands]
  end

  @type t :: :none | Predicate.t() | PrecedencePredicate.t() | And.t() | Or.t()
  @type evaluator :: (Predicate.t() | PrecedencePredicate.t() -> boolean())

  @doc "The empty semantic context, satisfied unconditionally."
  @spec none() :: :none
  def none, do: :none

  @doc """
  Evaluates `context` to a boolean using `evaluator` for leaf predicates.
  """
  @spec eval(t(), evaluator()) :: boolean()
  def eval(:none, _evaluator), do: true
  def eval(%Predicate{} = predicate, evaluator), do: evaluator.(predicate)
  def eval(%PrecedencePredicate{} = predicate, evaluator), do: evaluator.(predicate)
  def eval(%And{operands: operands}, evaluator), do: Enum.all?(operands, &eval(&1, evaluator))
  def eval(%Or{operands: operands}, evaluator), do: Enum.any?(operands, &eval(&1, evaluator))

  @doc """
  Simplifies `context` given that precedence predicates are evaluated now.

  Returns the reduced context, or `nil` if the context becomes false. A
  satisfied precedence predicate reduces to `:none`; a failed one to `nil`.
  """
  @spec eval_precedence(t(), evaluator()) :: t() | nil
  def eval_precedence(:none, _evaluator), do: :none
  def eval_precedence(%Predicate{} = predicate, _evaluator), do: predicate

  def eval_precedence(%PrecedencePredicate{} = predicate, evaluator) do
    if evaluator.(predicate), do: :none, else: nil
  end

  def eval_precedence(%And{operands: operands}, evaluator) do
    reduce_precedence(operands, evaluator, &and_op/2, :none, nil)
  end

  def eval_precedence(%Or{operands: operands}, evaluator) do
    reduce_precedence(operands, evaluator, &or_op/2, nil, :none)
  end

  @doc """
  Conjoins two contexts, dropping `:none` and reducing trivial cases.
  """
  @spec and_op(t() | nil, t() | nil) :: t() | nil
  def and_op(nil, _b), do: nil
  def and_op(_a, nil), do: nil
  def and_op(:none, b), do: b
  def and_op(a, :none), do: a
  def and_op(a, b), do: combine(%And{operands: flatten(And, a) ++ flatten(And, b)})

  @doc """
  Disjoins two contexts, with `:none` absorbing to `:none`.
  """
  @spec or_op(t() | nil, t() | nil) :: t() | nil
  def or_op(:none, _b), do: :none
  def or_op(_a, :none), do: :none
  def or_op(nil, b), do: b
  def or_op(a, nil), do: a
  def or_op(a, b), do: combine(%Or{operands: flatten(Or, a) ++ flatten(Or, b)})

  # Evaluates each operand's precedence form, short-circuiting on the
  # `absorbing` result (false for AND, true for OR) and dropping `neutral`.
  defp reduce_precedence(operands, evaluator, combine, neutral, absorbing) do
    Enum.reduce_while(operands, neutral, fn operand, acc ->
      case eval_precedence(operand, evaluator) do
        ^absorbing -> {:halt, absorbing}
        reduced -> {:cont, combine.(acc, reduced)}
      end
    end)
  end

  defp flatten(kind, %{__struct__: kind, operands: operands}), do: operands
  defp flatten(_kind, context), do: [context]

  defp combine(%{operands: operands} = combined) do
    case Enum.uniq(operands) do
      [single] -> single
      reduced -> %{combined | operands: reduced}
    end
  end
end
