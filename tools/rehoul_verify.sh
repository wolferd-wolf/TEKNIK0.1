#!/usr/bin/env bash
# Rehoul verification runner: import once, then run every affected gate.
# Prints ALL_GATES_GREEN on success (used by GATES.md G8).
set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$(command -v godot || echo /tmp/godot/godot)}"

echo "== godot import pass =="
timeout 240 "$GODOT" --headless --path . --import > /tmp/rehoul_import.log 2>&1
IMPORT_CODE=$?
if [ $IMPORT_CODE -ne 0 ]; then
  echo "IMPORT_FAILED exit=$IMPORT_CODE"
  tail -20 /tmp/rehoul_import.log
  exit 1
fi
if grep -E "SCRIPT ERROR|Parse Error" /tmp/rehoul_import.log > /tmp/rehoul_script_errors.txt; then
  echo "SCRIPT_ERRORS:"
  cat /tmp/rehoul_script_errors.txt | head -30
  exit 1
fi

HEADLESS_GATES=(
  tests/inventory_rehoul_gate.gd
  tests/inventory_redo_gate.gd
  tests/smelting_gate.gd
)
# These two capture screenshots of the rendered UI: CI runs them under
# xvfb-run (acceptance-gate.yml), not --headless. Mirror that here.
RENDERED_GATES=(
  tests/inventory_hotbar_step4_gate.gd
  tests/inventory_crafting_step5_gate.gd
)

OVERALL=0
run_gate() {
  local gate="$1"; shift
  local name; name="$(basename "$gate")"
  echo "== $name =="
  timeout 240 "$@" > "/tmp/rehoul_${name%.gd}.log" 2>&1
  local code=$?
  tail -3 "/tmp/rehoul_${name%.gd}.log"
  if [ $code -ne 0 ]; then
    echo "GATE_FAIL $name exit=$code"
    OVERALL=1
  fi
}

for gate in "${HEADLESS_GATES[@]}"; do
  run_gate "$gate" "$GODOT" --headless --path . --script "res://$gate"
done

if command -v xvfb-run > /dev/null 2>&1; then
  for gate in "${RENDERED_GATES[@]}"; do
    run_gate "$gate" xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" \
      --audio-driver Dummy --path . --script "res://$gate"
  done
else
  echo "NO_XVFB: skipping rendered gates (CI covers them)"
fi

if [ $OVERALL -eq 0 ]; then
  echo "ALL_GATES_GREEN"
else
  echo "SOME_GATES_RED"
fi
exit $OVERALL
