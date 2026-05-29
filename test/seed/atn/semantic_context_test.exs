defmodule Seed.ATN.SemanticContextTest do
  use ExUnit.Case, async: true

  alias Seed.ATN.SemanticContext, as: SC
  alias Seed.ATN.SemanticContext.{And, Or, PrecedencePredicate, Predicate}

  defp prec(p), do: %PrecedencePredicate{precedence: p}
  defp pred(r, i), do: %Predicate{rule_index: r, pred_index: i, ctx_dependent: false}

  describe "eval/2" do
    test "none is always true" do
      assert SC.eval(:none, fn _ -> false end)
    end

    test "a leaf predicate defers to the evaluator" do
      assert SC.eval(pred(0, 0), fn _ -> true end)
      refute SC.eval(pred(0, 0), fn _ -> false end)
    end

    test "and is conjunction, or is disjunction" do
      always = fn %PrecedencePredicate{precedence: p} -> p <= 2 end

      assert SC.eval(%And{operands: [prec(1), prec(2)]}, always)
      refute SC.eval(%And{operands: [prec(1), prec(3)]}, always)
      assert SC.eval(%Or{operands: [prec(3), prec(2)]}, always)
      refute SC.eval(%Or{operands: [prec(3), prec(4)]}, always)
    end
  end

  describe "eval_precedence/2" do
    test "a satisfied precedence predicate simplifies to none" do
      assert SC.eval_precedence(prec(2), fn _ -> true end) == :none
    end

    test "an unsatisfied precedence predicate is filtered to nil" do
      assert SC.eval_precedence(prec(2), fn _ -> false end) == nil
    end

    test "none stays none and a plain predicate is unchanged" do
      assert SC.eval_precedence(:none, fn _ -> true end) == :none
      assert SC.eval_precedence(pred(1, 0), fn _ -> false end) == pred(1, 0)
    end
  end

  describe "and_op/2 and or_op/2" do
    test "none is the identity for and; nil absorbs" do
      assert SC.and_op(:none, pred(0, 0)) == pred(0, 0)
      assert SC.and_op(pred(0, 0), :none) == pred(0, 0)
      assert SC.and_op(nil, pred(0, 0)) == nil
    end

    test "none absorbs for or; nil is the identity" do
      assert SC.or_op(:none, pred(0, 0)) == :none
      assert SC.or_op(nil, pred(0, 0)) == pred(0, 0)
    end

    test "and_op combines distinct predicates and dedups equal ones" do
      assert %And{operands: [a, b]} = SC.and_op(prec(1), prec(2))
      assert a == prec(1) and b == prec(2)
      assert SC.and_op(prec(1), prec(1)) == prec(1)
    end
  end
end
