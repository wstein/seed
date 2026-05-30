#!/usr/bin/env bash
#
# Regenerate the parse-tree oracle fixtures under test/fixtures/parse/.
#
# For each grammar this script generates a Java parser with the canonical
# ANTLR4 tool, compiles it with scripts/ParseDump.java, parses the matching
# <name>.input from its start rule, and writes the resulting parse tree as
# a LISP-style string to <name>.tree. Seed's parser will be validated
# against these trees.
#
# Requires java, javac, and curl on PATH.
#
# Usage:
#   scripts/gen_parse_fixtures.sh
#
# Environment:
#   ANTLR_VERSION  ANTLR4 release to use (default 4.13.2).
#   ANTLR_JAR      Path to an antlr4 complete jar. Downloaded to a cache
#                  under ./.antlr/ from Maven Central when unset.
set -euo pipefail

ANTLR_VERSION="${ANTLR_VERSION:-4.13.2}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fixtures="test/fixtures/parse"
grammars="test/fixtures/atn/grammars"

if [[ -z "${ANTLR_JAR:-}" ]]; then
  ANTLR_JAR="$repo_root/.antlr/antlr4-${ANTLR_VERSION}-complete.jar"
  if [[ ! -f "$ANTLR_JAR" ]]; then
    mkdir -p "$repo_root/.antlr"
    url="https://repo1.maven.org/maven2/org/antlr/antlr4/${ANTLR_VERSION}/antlr4-${ANTLR_VERSION}-complete.jar"
    echo "Downloading $url"
    curl -fsSL -o "$ANTLR_JAR" "$url"
  fi
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

for grammar in Hello Expr Ctx JSON ModesLexer Modes Calc MiscLexer Misc MoreLexer More SQLiteLexer SQLiteParser Erlang ElixirLexer ElixirParser; do
  cp "$grammars/$grammar.g4" "$workdir/"
done
cp scripts/ParseDump.java "$workdir/"

( cd "$workdir" && java -jar "$ANTLR_JAR" -Dlanguage=Java Hello.g4 Expr.g4 Ctx.g4 JSON.g4 ModesLexer.g4 Modes.g4 Calc.g4 MiscLexer.g4 Misc.g4 MoreLexer.g4 More.g4 SQLiteLexer.g4 SQLiteParser.g4 Erlang.g4 ElixirLexer.g4 ElixirParser.g4 )
echo "Compiling parsers and dumper"
( cd "$workdir" && javac -classpath "$ANTLR_JAR" ./*.java )

# Each entry maps a fixture base name to its grammar prefix and start rule
# as "name:Grammar:startRule" (bash 3.2 portable). The Ctx grammar is
# context-sensitive, so it has one fixture per call context.
for entry in "hello:Hello:greeting" "expr:Expr:prog" "ctx_a:Ctx:s" "ctx_b:Ctx:s" "json:JSON:json" "modes:Modes:prog" "calc:Calc:prog" "misc:Misc:prog" "more:More:prog" "sql:SQLite:parse" "sql2:SQLite:parse" "erl:Erlang:forms" "elixir:Elixir:parse"; do
  name="${entry%%:*}"
  rest="${entry#*:}"
  grammar="${rest%%:*}"
  start="${rest##*:}"
  java -classpath "$workdir:$ANTLR_JAR" ParseDump "$grammar" "$start" \
    < "$fixtures/$name.input" > "$fixtures/$name.tree"
  echo "$fixtures/$name.tree"
done

echo "Parse-tree fixtures regenerated under $fixtures"
