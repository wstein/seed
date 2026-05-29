defmodule Seed.IntervalSet do
  @moduledoc """
  An immutable set of integers stored as merged, inclusive intervals.

  ANTLR uses interval sets to represent the symbols a set or not-set
  transition matches. Intervals are kept sorted and non-overlapping;
  adjacent or overlapping ranges are merged on insertion. EOF is the
  integer `-1` and may be a member like any other value.

      iex> set = Seed.IntervalSet.new() |> Seed.IntervalSet.add_range(?a, ?f)
      iex> Seed.IntervalSet.member?(set, ?c)
      true
      iex> Seed.IntervalSet.member?(set, ?z)
      false
  """

  @type interval :: {integer(), integer()}
  @type t :: %__MODULE__{intervals: [interval()]}

  defstruct intervals: []

  @doc "Returns an empty interval set."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Adds the single value `value` to the set."
  @spec add_one(t(), integer()) :: t()
  def add_one(%__MODULE__{} = set, value) when is_integer(value) do
    add_range(set, value, value)
  end

  @doc """
  Adds the inclusive range `from..to` to the set, merging as needed.

  A range with `from > to` is ignored, matching the reference runtime.
  """
  @spec add_range(t(), integer(), integer()) :: t()
  def add_range(%__MODULE__{} = set, from, to) when from > to, do: set

  def add_range(%__MODULE__{intervals: intervals}, from, to) do
    %__MODULE__{intervals: merge([{from, to} | intervals])}
  end

  @doc "Returns `true` when `value` lies within one of the set's intervals."
  @spec member?(t(), integer()) :: boolean()
  def member?(%__MODULE__{intervals: intervals}, value) when is_integer(value) do
    Enum.any?(intervals, fn {lo, hi} -> value >= lo and value <= hi end)
  end

  @doc "Returns the merged, sorted intervals as a list of inclusive tuples."
  @spec intervals(t()) :: [interval()]
  def intervals(%__MODULE__{intervals: intervals}), do: intervals

  # Sorts intervals and coalesces overlapping or adjacent ones so the set
  # stays canonical regardless of insertion order.
  defp merge(intervals) do
    intervals
    |> Enum.sort()
    |> Enum.reduce([], fn
      interval, [] ->
        [interval]

      {lo, hi}, [{plo, phi} | rest] when lo <= phi + 1 ->
        [{plo, max(phi, hi)} | rest]

      interval, acc ->
        [interval | acc]
    end)
    |> Enum.reverse()
  end
end
