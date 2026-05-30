#!/usr/bin/env bash
#
# Regenerate the error-recovery oracle fixtures under test/fixtures/recover/.
#
# Each <name>.input is *malformed*. ANTLR's DefaultErrorStrategy recovers and
# still builds a tree (with error nodes and fabricated <missing X> tokens);
# scripts/ParseDump.java dumps that recovered tree to <name>.tree. Seed's
# parser — which always recovers, returning the partial tree alongside its
# diagnostics — is validated against these trees.
#
# Requires java, javac, and curl on PATH.
#
# Usage:
#   scripts/gen_recover_fixtures.sh
#
# Environment:
#   ANTLR_VERSION  ANTLR4 release to use (default 4.13.2).
#   ANTLR_JAR      Path to an antlr4 complete jar. Downloaded to a cache
#                  under ./.antlr/ from Maven Central when unset.
set -euo pipefail

ANTLR_VERSION="${ANTLR_VERSION:-4.13.2}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fixtures="test/fixtures/recover"
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

for grammar in Expr Calc JSON; do
  cp "$grammars/$grammar.g4" "$workdir/"
done
cp scripts/ParseDump.java "$workdir/"

( cd "$workdir" && java -jar "$ANTLR_JAR" -Dlanguage=Java Expr.g4 Calc.g4 JSON.g4 )
echo "Compiling parsers and dumper"
( cd "$workdir" && javac -classpath "$ANTLR_JAR" ./*.java )

# "name:Grammar:startRule" — the malformed input exercises a recovery path.
for entry in \
  "expr_missing_semi:Expr:prog" \
  "expr_missing_eq:Expr:prog" \
  "expr_extra_tok:Expr:prog" \
  "expr_no_expr:Expr:prog" \
  "json_unclosed:JSON:json" \
  "json_no_value:JSON:json" \
  "calc_missing_operand:Calc:prog"; do
  name="${entry%%:*}"
  rest="${entry#*:}"
  grammar="${rest%%:*}"
  start="${rest##*:}"
  java -classpath "$workdir:$ANTLR_JAR" ParseDump "$grammar" "$start" \
    < "$fixtures/$name.input" > "$fixtures/$name.tree"
  echo "$fixtures/$name.tree"
done

echo "Error-recovery fixtures regenerated under $fixtures"
