#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

# Use a temp dir for test cache
export GLASSBOX_DIR=$(mktemp -d)
export CACHE_DIR="$GLASSBOX_DIR/cache"
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

# Source glassbox functions
# set +e: glassbox.sh uses set -euo pipefail; disable errexit after sourcing
# so ((PASS++)) starting from 0 doesn't exit the test shell.
source "$SCRIPT_DIR/glassbox.sh" --source-only 2>/dev/null
set +e

# Test: cache_key produces a hash
key=$(cache_key "Bash:git status")
assert_eq "cache_key returns non-empty" "true" "$([ -n "$key" ] && echo true || echo false)"
assert_eq "cache_key is 16 chars" "16" "${#key}"

# Test: same input produces same key
key2=$(cache_key "Bash:git status")
assert_eq "cache_key is deterministic" "$key" "$key2"

# Test: different input produces different key
key3=$(cache_key "Bash:git log")
assert_eq "different input, different key" "true" "$([ "$key" != "$key3" ] && echo true || echo false)"

# Test: cache_store and cache_lookup
cache_store "$key" "Checking repository status
git status shows which files have been modified, staged, or are untracked."
result=$(cache_lookup "$key")
assert_eq "cache round-trip line 1" "Checking repository status" "$(echo "$result" | head -1)"

# Test: cache miss returns empty
result=$(cache_lookup "nonexistent1234")
assert_eq "cache miss is empty" "" "$result"

# Cleanup
rm -rf "$GLASSBOX_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
