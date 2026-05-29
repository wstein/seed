#!/usr/bin/env bash
#
# Regenerate the lexer token-oracle fixtures under test/fixtures/lex/.
#
# For each grammar in test/fixtures/atn/grammars/ this script generates a
# Java lexer with the canonical ANTLR4 tool, compiles it together with
# scripts/LexDump.java, and tokenizes the matching <name>.input file,
# writing the reference token list to <name>.tokens.json. Seed's own lexer
# is validated against these tokens (see test/fixtures/lex/README.md).
#
# Requires java, javac, and curl on PATH.
#
# Usage:
#   scripts/gen_lex_fixtures.sh
#
# Environment:
#   ANTLR_VERSION  ANTLR4 release to use (default 4.13.2).
#   ANTLR_JAR      Path to an antlr4 complete jar. Downloaded to a cache
#                  under ./.antlr/ from Maven Central when unset.
set -euo pipefail

ANTLR_VERSION="${ANTLR_VERSION:-4.13.2}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fixtures="test/fixtures/lex"
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

for grammar in Hello Expr Cover; do
  cp "$grammars/$grammar.g4" "$workdir/"
done
cp scripts/LexDump.java "$workdir/"

( cd "$workdir" && java -jar "$ANTLR_JAR" -Dlanguage=Java Hello.g4 Expr.g4 Cover.g4 )
echo "Compiling lexers and dumper"
( cd "$workdir" && javac -classpath "$ANTLR_JAR" ./*.java )

# Each entry maps a fixture base name to its grammar (bash 3.2 portable).
for pair in "hello:hello" "expr:expr" "cover:cover"; do
  name="${pair%%:*}"
  grammar="${pair##*:}"
  java -classpath "$workdir:$ANTLR_JAR" LexDump "$grammar" \
    < "$fixtures/$name.input" > "$fixtures/$name.tokens.json"
  echo "$fixtures/$name.tokens.json"
done

echo "Lexer fixtures regenerated under $fixtures"
