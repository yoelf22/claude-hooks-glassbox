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

# Bash: keeps command + flags, strips positional args
input='{"tool_name":"Bash","tool_input":{"command":"git checkout -b my-feature"}}'
result=$(echo "$input" | bash "$SCRIPT_DIR/glassbox.sh" --normalize-only 2>/dev/null)
assert_eq "git checkout -b normalized" "Bash:git checkout -b" "$result"

# Bash: strips file paths
input='{"tool_name":"Bash","tool_input":{"command":"cat /etc/passwd"}}'
result=$(echo "$input" | bash "$SCRIPT_DIR/glassbox.sh" --normalize-only 2>/dev/null)
assert_eq "cat strips path" "Bash:cat" "$result"

# Bash: keeps flags like -rf
input='{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/build"}}'
result=$(echo "$input" | bash "$SCRIPT_DIR/glassbox.sh" --normalize-only 2>/dev/null)
assert_eq "rm -rf keeps flags" "Bash:rm -rf" "$result"

# Bash: compound commands keep both commands
input='{"tool_name":"Bash","tool_input":{"command":"npm install && npm test"}}'
result=$(echo "$input" | bash "$SCRIPT_DIR/glassbox.sh" --normalize-only 2>/dev/null)
assert_eq "compound keeps both commands" "Bash:npm install && npm test" "$result"

# Non-Bash: keeps param keys only, sorted
input='{"tool_name":"Read","tool_input":{"file_path":"/src/app.ts","offset":50,"limit":100}}'
result=$(echo "$input" | bash "$SCRIPT_DIR/glassbox.sh" --normalize-only 2>/dev/null)
assert_eq "Read param keys" "Read:file_path,limit,offset" "$result"

# Grep: keeps param keys sorted
input='{"tool_name":"Grep","tool_input":{"pattern":"handleClick","type":"tsx"}}'
result=$(echo "$input" | bash "$SCRIPT_DIR/glassbox.sh" --normalize-only 2>/dev/null)
assert_eq "Grep param keys" "Grep:pattern,type" "$result"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
