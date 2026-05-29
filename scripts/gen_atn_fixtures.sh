#!/usr/bin/env bash
#
# Regenerate the golden serialized-ATN fixtures under test/fixtures/atn/.
#
# For each grammar in test/fixtures/atn/grammars/ this script:
#   1. generates a Python3 parser/lexer with the canonical ANTLR4 tool,
#   2. extracts the serialized ATN integer array into <name>.atn, and
#   3. deserializes it with the tool's own runtime (scripts/AtnOracle.java)
#      to emit reference structural facts into <name>.oracle.json.
#
# The .atn files are the contract Seed's ATNDeserializer must read; the
# .oracle.json files are the reference Seed's output is validated against
# (see docs ADR-002). Requires java, javac, and python3 on PATH.
#
# Usage:
#   scripts/gen_atn_fixtures.sh
#
# Environment:
#   ANTLR_VERSION  ANTLR4 release to use (default 4.13.2).
#   ANTLR_JAR      Path to an antlr4 complete jar. Downloaded to a cache
#                  under ./.antlr/ from Maven Central when unset.
set -euo pipefail

ANTLR_VERSION="${ANTLR_VERSION:-4.13.2}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fixtures="test/fixtures/atn"
grammars="$fixtures/grammars"

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

echo "Compiling oracle"
javac -classpath "$ANTLR_JAR" -d "$workdir" scripts/AtnOracle.java

# Each entry maps a grammar file to its fixture base name as
# "Grammar:base" (kept as simple pairs for bash 3.2 portability).
for pair in "Hello:hello" "Expr:expr" "Cover:cover"; do
  grammar="${pair%%:*}"
  base="${pair##*:}"
  cp "$grammars/$grammar.g4" "$workdir/"
  ( cd "$workdir" && java -jar "$ANTLR_JAR" -Dlanguage=Python3 "$grammar.g4" )

  for kind in Parser Lexer; do
    py="$workdir/${grammar}${kind}.py"
    name="${base}_$(echo "$kind" | tr '[:upper:]' '[:lower:]')"
    python3 - "$py" "$fixtures/$name.atn" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"def serializedATN\(\):\s*return\s*\[(.*?)\]", src, re.S)
ints = [int(x) for x in re.findall(r"-?\d+", m.group(1))]
open(sys.argv[2], "w").write(",".join(map(str, ints)))
print(f"{sys.argv[2]}: {len(ints)} ints, version {ints[0]}")
PY
    ( cd "$fixtures" && java -classpath "$workdir:$ANTLR_JAR" AtnOracle "$name" > "$repo_root/$fixtures/$name.oracle.json" )
  done
done

echo "Fixtures regenerated under $fixtures"
