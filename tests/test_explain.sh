#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

export GLASSBOX_DIR=$(mktemp -d)

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
set +e

# Test: build_prompt for Bash tool includes tool name
prompt=$(build_prompt "Bash" "git status")
assert_eq "prompt mentions Bash" "true" "$(echo "$prompt" | grep -q 'Tool: Bash' && echo true || echo false)"
assert_eq "prompt mentions command" "true" "$(echo "$prompt" | grep -q 'git status' && echo true || echo false)"

# Test: build_prompt for non-Bash tool
prompt=$(build_prompt "Read" "file_path,offset,limit")
assert_eq "prompt mentions Read" "true" "$(echo "$prompt" | grep -q 'Tool: Read' && echo true || echo false)"

# Test: parse_response extracts BRIEF and EXTENDED
response="BRIEF: Checking repository status
EXTENDED: git status shows which files have been modified, staged for commit, or are not yet tracked by git."
brief=$(parse_response "$response" "brief")
extended=$(parse_response "$response" "extended")
assert_eq "parse brief" "Checking repository status" "$brief"
assert_eq "parse extended starts with git" "true" "$(echo "$extended" | grep -q '^git status' && echo true || echo false)"

rm -rf "$GLASSBOX_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
