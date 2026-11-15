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

echo "::group::Skript-Validierung (alle Skripte mit Autoloads kompilieren)"
"$GODOT" --headless --path "$PROJECT_DIR" -- --validate 2>&1 | tee validate.log
if ! grep -q "VALIDATION PASSED" validate.log; then
  echo "::error::Skript-Validierung fehlgeschlagen"
  grep -E "SCRIPT ERROR|Parse Error|Compile Error|VALIDATE FAIL|at: " validate.log | head -n 60
  FAIL=1
fi
echo "::endgroup::"

exit $FAIL
