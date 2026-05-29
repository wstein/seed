#!/usr/bin/env bash
#
# Regenerate the .interp grammar fixtures under test/fixtures/interp/.
#
# The ANTLR tool emits a <Grammar>.interp file per recognizer alongside the
# generated code: the serialized ATN plus token names, rule names, and (for
# lexers) channel and mode names. Seed loads these directly via Seed.Interp,
# so a grammar can be parsed at run time with no code generation.
#
# This script generates each grammar in test/fixtures/atn/grammars/ and
# copies the resulting *.interp files into test/fixtures/interp/.
#
# Requires java and curl on PATH.
#
# Usage:
#   scripts/gen_interp_fixtures.sh
#
# Environment:
#   ANTLR_VERSION  ANTLR4 release to use (default 4.13.2).
#   ANTLR_JAR      Path to an antlr4 complete jar. Downloaded to a cache
#                  under ./.antlr/ from Maven Central when unset.
set -euo pipefail

ANTLR_VERSION="${ANTLR_VERSION:-4.13.2}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fixtures="test/fixtures/interp"
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

mkdir -p "$fixtures"
for grammar in Hello Expr Cover Ctx JSON Pred LexPred Hidden G4; do
  cp "$grammars/$grammar.g4" "$workdir/"
done

( cd "$workdir" && java -jar "$ANTLR_JAR" -Dlanguage=Python3 Hello.g4 Expr.g4 Cover.g4 Ctx.g4 JSON.g4 Pred.g4 LexPred.g4 Hidden.g4 G4.g4 )

for interp in "$workdir"/*.interp; do
  cp "$interp" "$fixtures/"
  echo "$fixtures/$(basename "$interp")"
done

echo "Interp fixtures regenerated under $fixtures"
