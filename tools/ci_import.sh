#!/usr/bin/env bash
# Importiert das Godot-Projekt headless und prüft jedes GDScript einzeln.
# Bricht bei Parse-/Skript-/Shader-Fehlern mit Exit-Code 1 ab.
set -uo pipefail
PROJECT_DIR="${1:-game}"
GODOT="${GODOT:-godot}"

echo "::group::Import (1. Lauf: Cache + globale Klassen)"
"$GODOT" --headless --path "$PROJECT_DIR" --import > import1.log 2>&1 || true
tail -n 40 import1.log
echo "::endgroup::"

echo "::group::Import (2. Lauf: muss fehlerfrei sein)"
"$GODOT" --headless --path "$PROJECT_DIR" --import 2>&1 | tee import2.log
echo "::endgroup::"

FAIL=0
if grep -E "Parse Error|SCRIPT ERROR|Failed to load script|Compile Error|SHADER ERROR" import2.log; then
  echo "::error::Godot-Import meldet Skript-/Shader-Fehler"
  FAIL=1
fi

echo "::group::GDScript-Prüfung (--check-only)"
while IFS= read -r f; do
  rel="res://${f#"$PROJECT_DIR"/}"
  out=$("$GODOT" --headless --path "$PROJECT_DIR" --check-only --script "$rel" 2>&1)
  code=$?
  if [ $code -ne 0 ] || echo "$out" | grep -qE "Parse Error|SCRIPT ERROR|Compile Error"; then
    echo "::error file=$f::GDScript-Fehler in $rel"
    echo "$out" | grep -E "ERROR|Error|error" | head -n 20
    FAIL=1
  else
    echo "ok  $rel"
  fi
done < <(find "$PROJECT_DIR/scripts" -name '*.gd' | sort)
echo "::endgroup::"

exit $FAIL
