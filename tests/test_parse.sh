#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

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

# Test: extract tool_name from Bash tool call
input='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
result=$(echo "$input" | bash "$SCRIPT_DIR/glassbox.sh" --parse-only 2>/dev/null)
assert_eq "Bash tool_name" "Bash" "$(echo "$result" | head -1)"

# Test: extract tool_name from Read tool call
input='{"tool_name":"Read","tool_input":{"file_path":"/src/app.ts"}}'
result=$(echo "$input" | bash "$SCRIPT_DIR/glassbox.sh" --parse-only 2>/dev/null)
assert_eq "Read tool_name" "Read" "$(echo "$result" | head -1)"

# Test: malformed JSON exits cleanly
result=$(echo "not json" | bash "$SCRIPT_DIR/glassbox.sh" 2>/dev/null; echo $?)
assert_eq "malformed JSON exits 0" "0" "$result"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
