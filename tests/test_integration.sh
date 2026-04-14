#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

export GLASSBOX_DIR=$(mktemp -d)
export CACHE_DIR="$GLASSBOX_DIR/cache"
export LEARNED_FILE="$GLASSBOX_DIR/learned"
mkdir -p "$CACHE_DIR"

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

# Test: script exits 0 on valid input (even without claude CLI)
input='{"tool_name":"Grep","tool_input":{"pattern":"test","type":"js"}}'
echo "$input" | bash "$SCRIPT_DIR/glassbox.sh" 2>/dev/null
assert_eq "exits 0 on valid input" "0" "$?"

# Test: script exits 0 on malformed input
echo "garbage" | bash "$SCRIPT_DIR/glassbox.sh" 2>/dev/null
assert_eq "exits 0 on garbage" "0" "$?"

# Test: script exits 0 on empty input
echo "" | bash "$SCRIPT_DIR/glassbox.sh" 2>/dev/null
assert_eq "exits 0 on empty" "0" "$?"

# Test: pre-populate cache and verify it's used
source "$SCRIPT_DIR/glassbox.sh" --source-only 2>/dev/null
set +e
NORM=$(normalize "Read" '{"file_path":"/test"}')
KEY=$(cache_key "$NORM")
cache_store "$KEY" "Reading a file
Read loads file contents for Claude to examine."

output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"/test"}}' | bash "$SCRIPT_DIR/glassbox.sh" 2>&1 1>/dev/null)
assert_eq "cached output shown" "true" "$(echo "$output" | grep -q 'Reading a file' && echo true || echo false)"

# Test: learned tool skips extended
echo "Read" > "$LEARNED_FILE"
output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"/test"}}' | bash "$SCRIPT_DIR/glassbox.sh" 2>&1 1>/dev/null)
has_brief=$(echo "$output" | grep -q 'Reading a file' && echo true || echo false)
has_extended=$(echo "$output" | grep -q 'loads file contents' && echo true || echo false)
assert_eq "learned: brief shown" "true" "$has_brief"
assert_eq "learned: extended hidden" "false" "$has_extended"

rm -rf "$GLASSBOX_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
