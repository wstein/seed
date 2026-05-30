#!/usr/bin/env bash
#
# Regenerate the tree-pattern oracle fixtures under test/fixtures/pattern/.
#
# For each case this script generates a Java parser with the canonical ANTLR4
# tool, compiles it with scripts/PatternDump.java, compiles a tree pattern,
# runs it against the parsed <name>.input via find_all over an XPath, and
# writes the canonical match dump to <name>.dump. Seed's
# Seed.TreePatternMatcher is validated against these dumps.
#
# Requires java, javac, and curl on PATH.
#
# Usage:
#   scripts/gen_pattern_fixtures.sh
#
# Environment:
#   ANTLR_VERSION  ANTLR4 release to use (default 4.13.2).
#   ANTLR_JAR      Path to an antlr4 complete jar. Downloaded to a cache
#                  under ./.antlr/ from Maven Central when unset.
set -euo pipefail

ANTLR_VERSION="${ANTLR_VERSION:-4.13.2}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fixtures="test/fixtures/pattern"
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
cp scripts/PatternDump.java "$workdir/"

( cd "$workdir" && java -jar "$ANTLR_JAR" -Dlanguage=Java Expr.g4 Calc.g4 JSON.g4 )
echo "Compiling parsers and dumper"
( cd "$workdir" && javac -classpath "$ANTLR_JAR" ./*.java )

# Each entry is "name|Grammar|subjectStartRule|patternRule|xpath|pattern".
# '|' delimits because patterns use ':' (labels) and xpaths use '/'.
entries=(
  "expr_stat|Expr|prog|stat|//stat|<ID> = <expr>;"
  "expr_add|Expr|prog|expr|//expr|<expr> + <expr>"
  "expr_label|Expr|prog|stat|//stat|<lhs:ID> = <rhs:expr>;"
  "expr_int|Expr|prog|stat|//stat|<ID> = <INT>;"
  "calc_pow|Calc|prog|expr|//expr|<expr> ^ <expr>"
  "json_pair|JSON|json|pair|//pair|<STRING> : <value>"
)

for entry in "${entries[@]}"; do
  IFS='|' read -r name grammar start prule xpath pattern <<< "$entry"
  java -classpath "$workdir:$ANTLR_JAR" PatternDump \
    "$grammar" "$start" "$prule" "$xpath" "$pattern" \
    < "$fixtures/$name.input" > "$fixtures/$name.dump"
  echo "$fixtures/$name.dump"
done

echo "Tree-pattern fixtures regenerated under $fixtures"
