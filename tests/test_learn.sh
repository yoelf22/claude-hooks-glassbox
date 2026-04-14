#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

export GLASSBOX_DIR=$(mktemp -d)
export LEARNED_FILE="$GLASSBOX_DIR/learned"

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        ((FAIL++))
    fi
}

source "$SCRIPT_DIR/glassbox.sh" --source-only 2>/dev/null
set +e  # needed because set -euo pipefail propagates from source

# Test: nothing learned initially
assert_eq "not learned initially" "false" "$(is_learned "Read" && echo true || echo false)"

# Test: learn a tool
learn_tool "Read"
assert_eq "Read is learned" "true" "$(is_learned "Read" && echo true || echo false)"

# Test: other tools not affected
assert_eq "Grep not learned" "false" "$(is_learned "Grep" && echo true || echo false)"

# Test: learn a bash command pattern
learn_tool "Bash:git"
assert_eq "Bash:git is learned" "true" "$(is_learned "Bash:git" && echo true || echo false)"
assert_eq "Bash:npm not learned" "false" "$(is_learned "Bash:npm" && echo true || echo false)"

# Test: unlearn
unlearn_tool "Read"
assert_eq "Read unlearned" "false" "$(is_learned "Read" && echo true || echo false)"

rm -rf "$GLASSBOX_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
