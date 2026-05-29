defmodule Seed.ATN.PredictionContext do
  @moduledoc """
  The rule-invocation stack a configuration carries during ATN simulation.

  There are three forms, mirroring the reference runtime:

    * the empty context `:empty`, the bottom of the stack (`$`);
    * a singleton `%PredictionContext{parent: ctx, return_state: n}`, one
      rule invocation returning to ATN state `n`; and
    * an array `%PredictionContext.Array{}`, several alternative stacks that
      arose from merging, kept sorted by return state with the empty
      sentinel last.

  The lexer only ever produces the first two (it never merges). The parser
  produces arrays via `merge/3`, which combines two contexts under either
  SLL (`root_is_wildcard: true`) or full-LL (`false`) semantics. The merge
  is a faithful transliteration of the reference algorithm; it relies on
  Elixir's structural equality where the reference uses interning, so the
  context-interning step (`combineCommonParents`) is unnecessary.
  """

  @empty_return_state 0x7FFFFFFF

  defmodule Array do
    @moduledoc """
    Several alternative call stacks sharing a merge point.

    `return_states` is sorted ascending with `PredictionContext`'s empty
    sentinel last; `parents` is the matching list of parent contexts (the
    parent for the empty sentinel is `nil`).
    """
    @type t :: %__MODULE__{
            parents: [Seed.ATN.PredictionContext.t() | nil],
            return_states: [integer()]
          }
    @enforce_keys [:parents, :return_states]
    defstruct [:parents, :return_states]
  end

  @type t :: :empty | %__MODULE__{parent: t(), return_state: non_neg_integer()} | Array.t()

  @enforce_keys [:parent, :return_state]
  defstruct [:parent, :return_state]

  @doc "The sentinel return state marking the bottom of the stack (`$`)."
  @spec empty_return_state() :: pos_integer()
  def empty_return_state, do: @empty_return_state

  @doc "The empty context."
  @spec empty() :: :empty
  def empty, do: :empty

  @doc "Returns `true` only for the empty context."
  @spec empty?(t()) :: boolean()
  def empty?(:empty), do: true
  def empty?(_other), do: false

  @doc """
  Pushes a return to `return_state` onto `parent`.

  Collapses to `:empty` when pushing the empty sentinel onto the empty
  context, matching the reference factory.
  """
  @spec singleton(t(), integer()) :: t()
  def singleton(:empty, @empty_return_state), do: :empty
  def singleton(parent, return_state), do: %__MODULE__{parent: parent, return_state: return_state}

  @doc "The number of alternative stacks in `context`."
  @spec size(t()) :: pos_integer()
  def size(:empty), do: 1
  def size(%__MODULE__{}), do: 1
  def size(%Array{return_states: return_states}), do: length(return_states)

  @doc "The return state of the `index`-th alternative stack."
  @spec return_state(t(), non_neg_integer()) :: integer()
  def return_state(:empty, 0), do: @empty_return_state
  def return_state(%__MODULE__{return_state: return_state}, 0), do: return_state
  def return_state(%Array{return_states: return_states}, index), do: Enum.at(return_states, index)

  @doc "The parent context of the `index`-th alternative stack."
  @spec parent(t(), non_neg_integer()) :: t() | nil
  def parent(:empty, 0), do: nil
  def parent(%__MODULE__{parent: parent}, 0), do: parent
  def parent(%Array{parents: parents}, index), do: Enum.at(parents, index)

  @doc "Returns `true` when `context` has the empty sentinel as a stack."
  @spec has_empty_path?(t()) :: boolean()
  def has_empty_path?(context),
    do: return_state(context, size(context) - 1) == @empty_return_state

  @doc """
  Merges two contexts.

  `root_is_wildcard` selects the semantics: `true` for SLL (the empty
  context is a wildcard that absorbs the other), `false` for full LL (empty
  contexts are preserved as distinct `$` stacks).
  """
  @spec merge(t(), t(), boolean()) :: t()
  def merge(a, b, _root_is_wildcard) when a == b, do: a

  def merge(a, b, root_is_wildcard) do
    if singleton_like?(a) and singleton_like?(b) do
      merge_singletons(a, b, root_is_wildcard)
    else
      merge_arrays(to_array(a), to_array(b), root_is_wildcard)
    end
  end

  defp singleton_like?(:empty), do: true
  defp singleton_like?(%__MODULE__{}), do: true
  defp singleton_like?(%Array{}), do: false

  defp to_array(%Array{} = array), do: array

  defp to_array(context),
    do: %Array{parents: [parent(context, 0)], return_states: [return_state(context, 0)]}

  # --- Singleton merge ----------------------------------------------------

  defp merge_singletons(a, b, root_is_wildcard) do
    case merge_root(a, b, root_is_wildcard) do
      :none -> merge_singleton_payloads(a, b, root_is_wildcard)
      merged -> merged
    end
  end

  defp merge_singleton_payloads(a, b, root_is_wildcard) do
    a_return = return_state(a, 0)
    b_return = return_state(b, 0)
    a_parent = parent(a, 0)
    b_parent = parent(b, 0)

    if a_return == b_return do
      merge_equal_returns(a, b, a_parent, b_parent, a_return, root_is_wildcard)
    else
      order_into_array(a_return, a_parent, b_return, b_parent)
    end
  end

  defp merge_equal_returns(a, b, a_parent, b_parent, return, root_is_wildcard) do
    merged_parent = merge(a_parent, b_parent, root_is_wildcard)

    cond do
      merged_parent == a_parent -> a
      merged_parent == b_parent -> b
      true -> singleton(merged_parent, return)
    end
  end

  defp order_into_array(a_return, a_parent, b_return, b_parent) do
    if a_return > b_return do
      %Array{parents: [b_parent, a_parent], return_states: [b_return, a_return]}
    else
      %Array{parents: [a_parent, b_parent], return_states: [a_return, b_return]}
    end
  end

  # Handles merges involving the empty context, returning `:none` when
  # neither operand is empty.
  defp merge_root(a, b, true) do
    if a == :empty or b == :empty, do: :empty, else: :none
  end

  defp merge_root(:empty, :empty, false), do: :empty

  defp merge_root(:empty, b, false) do
    %Array{parents: [parent(b, 0), nil], return_states: [return_state(b, 0), @empty_return_state]}
  end

  defp merge_root(a, :empty, false) do
    %Array{parents: [parent(a, 0), nil], return_states: [return_state(a, 0), @empty_return_state]}
  end

  defp merge_root(_a, _b, false), do: :none

  # --- Array merge --------------------------------------------------------

  defp merge_arrays(
         %Array{parents: ap, return_states: ar},
         %Array{parents: bp, return_states: br},
         root_is_wildcard
       ) do
    {parents, returns} = merge_sorted(ap, ar, bp, br, root_is_wildcard, [], [])
    build(parents, returns)
  end

  defp merge_sorted([], [], bp, br, _root, pacc, racc),
    do: {Enum.reverse(pacc) ++ bp, Enum.reverse(racc) ++ br}

  defp merge_sorted(ap, ar, [], [], _root, pacc, racc),
    do: {Enum.reverse(pacc) ++ ap, Enum.reverse(racc) ++ ar}

  defp merge_sorted([ap0 | apr], [ar0 | arr], [bp0 | bpr], [br0 | brr], root, pacc, racc) do
    cond do
      ar0 == br0 ->
        merged = merge_array_parents(ar0, ap0, bp0, root)
        merge_sorted(apr, arr, bpr, brr, root, [merged | pacc], [ar0 | racc])

      ar0 < br0 ->
        merge_sorted(apr, arr, [bp0 | bpr], [br0 | brr], root, [ap0 | pacc], [ar0 | racc])

      true ->
        merge_sorted([ap0 | apr], [ar0 | arr], bpr, brr, root, [bp0 | pacc], [br0 | racc])
    end
  end

  defp merge_array_parents(@empty_return_state, a_parent, _b_parent, _root), do: a_parent
  defp merge_array_parents(_return, parent, parent, _root), do: parent
  defp merge_array_parents(_return, a_parent, b_parent, root), do: merge(a_parent, b_parent, root)

  defp build([nil], [@empty_return_state]), do: :empty
  defp build([parent], [return]), do: singleton(parent, return)
  defp build(parents, returns), do: %Array{parents: parents, return_states: returns}
end
