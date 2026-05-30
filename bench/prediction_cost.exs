# Prediction-cost benchmark for the SLL readiness gate (Roadmap D / ADR-008).
#
# Complements bench/parse_throughput.exs (the must-not-regress JSON-flat
# baseline, where full-context cache reuse is ~80×) with the must-improve
# cases: varied/nested grammars where full context computes 2-12× redundant
# start-state closures (see notes/SLL Readiness). Any SLL attempt must show a
# before/after net win here without regressing parse_throughput.exs.
#
# Run with:  mix run bench/prediction_cost.exs

alias Seed.Interp

interp = Path.expand("../test/fixtures/interp", __DIR__)
load = fn g -> Interp.load!(Path.join(interp, g <> ".interp")) end

json = load.("JSON")
json_lex = load.("JSONLexer")
sql = load.("SQLiteParser")
sql_lex = load.("SQLiteLexer")

nested_json =
  "[" <>
    Enum.map_join(1..200, ",", fn i ->
      ~s({"id":#{i},"kids":[{"a":[1,2,{"b":#{i}}]},{"c":{"d":[#{i},#{i + 1}]}}]})
    end) <> "]"

big_sql =
  "SELECT " <>
    Enum.map_join(1..200, ", ", fn i -> "a#{i}+b#{i}*(c#{i}-d#{i})/e#{i}" end) <>
    " FROM t WHERE " <>
    Enum.map_join(1..120, " AND ", fn i -> "x#{i} > #{i}*2 OR y#{i} < #{i}+1" end) <> ";"

cases = [
  {"json_flat (must-not-regress)", json, json_lex, 0,
   "[" <> Enum.map_join(1..5000, ",", &Integer.to_string/1) <> "]"},
  {"json_nested (must-improve)", json, json_lex, 0, nested_json},
  {"sql_big (must-improve)", sql, sql_lex, 0, big_sql}
]

time = fn parser, lexer, rule, input ->
  # warm the shared DFA cache, then take the best of three.
  Seed.parse(parser, lexer, input, rule)

  1..3
  |> Enum.map(fn _ ->
    {us, {tag, _, _}} =
      :timer.tc(fn ->
        case Seed.parse(parser, lexer, input, rule) do
          {:ok, tree} -> {:ok, tree, nil}
          other -> other
        end
      end)

    {us, tag}
  end)
  |> Enum.min_by(&elem(&1, 0))
end

IO.puts("prediction-cost baseline (interpreter, best of 3)\n")

for {name, parser, lexer, rule, input} <- cases do
  {us, _tag} = time.(parser, lexer, rule, input)

  IO.puts(
    String.pad_trailing(name, 30) <>
      "  #{Float.round(us / 1000, 1)} ms  (#{byte_size(input)} bytes)"
  )
end
