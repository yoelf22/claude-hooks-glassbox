#!/bin/bash
set -euo pipefail

GLASSBOX_DIR="${GLASSBOX_DIR:-${HOME}/.glassbox}"
CACHE_DIR="${CACHE_DIR:-${GLASSBOX_DIR}/cache}"
LEARNED_FILE="${LEARNED_FILE:-${GLASSBOX_DIR}/learned}"

# === Functions ===

# normalize TOOL_NAME TOOL_INPUT_JSON
# Produces a stable string for cache key generation by stripping user-specific values.
#
# For Bash: keeps program name and flags (words starting with -), strips positional args.
# For compound commands (&&, ||, ;): processes each sub-command the same way.
# For non-Bash tools: keeps sorted parameter keys, strips values.
normalize() {
    local tool_name="$1"
    local tool_input="$2"

    if [ "$tool_name" = "Bash" ]; then
        local command
        command=$(echo "$tool_input" | jq -r '.command // empty' 2>/dev/null) || {
            echo "${tool_name}:"
            return
        }

        # Split compound commands on &&, ||, or ; while preserving the operators.
        # Use awk to tokenize, replacing operators with a sentinel that includes the op.
        # Approach: use awk to insert newlines before operators, then process line by line.
        local normalized_parts=()
        local ops=()

        # Use awk to split the command into alternating [segment, op, segment, op, ...]
        # We emit lines like: "SEG:<text>" or "OP:<text>"
        local parsed
        parsed=$(echo "$command" | awk '
        {
            line = $0
            out = ""
            i = 1
            while (i <= length(line)) {
                c2 = substr(line, i, 2)
                c1 = substr(line, i, 1)
                if (c2 == "&&" || c2 == "||") {
                    print "SEG:" out
                    print "OP:" c2
                    out = ""
                    i += 2
                    # skip surrounding spaces
                    while (substr(line, i, 1) == " ") i++
                } else if (c1 == ";") {
                    print "SEG:" out
                    print "OP:;"
                    out = ""
                    i += 1
                    while (substr(line, i, 1) == " ") i++
                } else {
                    out = out c1
                    i++
                }
            }
            print "SEG:" out
        }
        ')

        local result=""
        local pending_op=""
        while IFS= read -r line; do
            local prefix="${line:0:4}"  # "SEG:" or "OP:x" where x is first char of op
            local val="${line:4}"
            if [ "$prefix" = "SEG:" ]; then
                local normalized_seg
                normalized_seg=$(_normalize_bash_segment "$val")
                if [ -z "$result" ]; then
                    result="$normalized_seg"
                else
                    result="${result} ${pending_op} ${normalized_seg}"
                fi
                pending_op=""
            else
                # Line starts with "OP:" — operator is everything after the 3-char "OP:" prefix
                pending_op="${line:3}"
            fi
        done <<< "$parsed"

        echo "Bash:${result}"
    else
        # Non-Bash: extract sorted parameter keys
        local keys
        keys=$(echo "$tool_input" | jq -r 'keys | sort | join(",")' 2>/dev/null) || keys=""
        echo "${tool_name}:${keys}"
    fi
}

# _normalize_bash_segment SEGMENT
# Strips positional args from a single (non-compound) bash command segment.
#
# Rules (derived from spec examples):
#   - First word (command name) is always kept.
#   - Words starting with - are kept (flags).
#   - A word that immediately follows a single-char flag (-X, -b, etc.) is kept
#     as the flag's value IF the following word does not look like a path/URL/file:
#       * does not start with /
#       * does not contain a dot followed by alphanumeric (e.g. file.ts, api.example.com)
#       * does not look like a git branch/identifier with hyphens that are not flags
#     Spec examples:
#       curl -X POST https://api.example.com  → curl -X POST   (POST kept, URL stripped)
#       git checkout -b my-feature            → git checkout -b  (my-feature stripped)
#       rm -rf /tmp/build                     → rm -rf           (-rf is a combined flag)
#
# Simplest rule matching all spec examples:
#   Keep a non-flag word after a flag ONLY if it is all uppercase (like POST, GET, PUT).
#   Everything else after a flag is treated as a positional arg and stripped.
# _normalize_bash_segment SEGMENT
# Strips positional args from a single (non-compound) bash command segment.
#
# Rules (derived from spec examples):
#   - All words before the first flag are kept (program name + subcommands).
#     e.g.: "git checkout -b my-feature" → keep "git checkout" (before first flag "-b")
#   - Flag words (starting with -) are always kept.
#   - A non-flag word that comes immediately after a flag is kept ONLY if it is
#     all-uppercase (HTTP methods like POST, GET, PUT). Otherwise it is stripped.
#   Spec examples:
#     git checkout -b my-feature           → git checkout -b
#     cat /etc/passwd                      → cat         (no flags; /etc/passwd after cmd)
#     rm -rf /tmp/build                    → rm -rf
#     npm install && npm test              → npm install && npm test
#     curl -X POST https://api.example.com → curl -X POST
_normalize_bash_segment() {
    local seg="$1"
    # Trim surrounding whitespace
    seg="${seg#"${seg%%[![:space:]]*}"}"
    seg="${seg%"${seg##*[![:space:]]}"}"

    [ -z "$seg" ] && return

    local words=()
    read -ra words <<< "$seg"

    local result=()
    local seen_flag=false
    local prev_was_flag=false
    for word in "${words[@]}"; do
        if [[ "$word" == -* ]]; then
            result+=("$word")
            seen_flag=true
            prev_was_flag=true
        elif ! $seen_flag; then
            # Before any flag: keep subcommands, strip path/URL arguments.
            # A word is a path/URL if it starts with / . ~ or contains ://
            if [[ "$word" == /* ]] || [[ "$word" == ./* ]] || [[ "$word" == ../* ]] || \
               [[ "$word" == ~/* ]] || [[ "$word" == *://* ]]; then
                : # path/URL positional arg — strip it
            else
                result+=("$word")
            fi
            prev_was_flag=false
        elif $prev_was_flag && [[ "$word" =~ ^[A-Z]+$ ]]; then
            # All-uppercase word right after a flag → HTTP method constant, keep it
            result+=("$word")
            prev_was_flag=false
        else
            # Positional arg after a flag — strip it
            prev_was_flag=false
        fi
    done

    echo "${result[*]}"
}

# Check if a tool (or tool:command pattern) is marked as learned
is_learned() {
    local pattern="$1"
    [ -f "$LEARNED_FILE" ] || return 1
    # Check exact match
    grep -qFx "$pattern" "$LEARNED_FILE" 2>/dev/null && return 0
    # Check if the base tool is learned (e.g., "Read" matches "Read:file_path,offset")
    local base="${pattern%%:*}"
    grep -qFx "$base" "$LEARNED_FILE" 2>/dev/null && return 0
    # For Bash: check if the base command is learned (e.g., "Bash:git" matches "Bash:git checkout -b")
    if [ "$base" = "Bash" ]; then
        local cmd="${pattern#Bash:}"
        local first_word="${cmd%% *}"
        grep -qFx "Bash:${first_word}" "$LEARNED_FILE" 2>/dev/null && return 0
    fi
    return 1
}

# Mark a tool as learned
learn_tool() {
    mkdir -p "$GLASSBOX_DIR"
    echo "$1" >> "$LEARNED_FILE"
}

# Remove a tool from learned list
unlearn_tool() {
    [ -f "$LEARNED_FILE" ] || return 0
    local tmp="${LEARNED_FILE}.tmp"
    grep -vFx "$1" "$LEARNED_FILE" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$LEARNED_FILE"
}

# Generate a 16-char hex cache key from a normalized string
cache_key() {
    echo -n "$1" | shasum -a 256 | cut -c1-16
}

# Look up a cached explanation. Returns empty string on miss.
cache_lookup() {
    local key="$1"
    local file="${CACHE_DIR}/${key}"
    if [ -f "$file" ]; then
        cat "$file"
    fi
}

# Store an explanation in the cache.
cache_store() {
    local key="$1"
    local content="$2"
    mkdir -p "$CACHE_DIR"
    echo "$content" > "${CACHE_DIR}/${key}"
}

# Purge cache entries older than 30 days.
cache_cleanup() {
    [ -d "$CACHE_DIR" ] && find "$CACHE_DIR" -type f -mtime +30 -delete 2>/dev/null
}

# Build the LLM prompt for generating an explanation
build_prompt() {
    local tool="$1"
    local normalized_input="$2"
    local prompt="You are glassBox, explaining Claude Code tools to a non-technical user.

Tool: ${tool}
Input: ${normalized_input}

Respond with exactly two sections:
BRIEF: A one-liner (max 10 words) of what this does.
EXTENDED: A plain-English explanation of the command/tool and its flags/arguments. Do not include specific file paths, URLs, branch names, or user values. Explain what the arguments DO, not what they ARE. Keep it under 60 words."

    # For Bash commands, try to enrich with man/help output
    if [ "$tool" = "Bash" ]; then
        local base_cmd="${normalized_input%% *}"
        local ref=""
        ref=$(man "$base_cmd" 2>/dev/null | head -30) || \
        ref=$("$base_cmd" --help 2>&1 | head -20) || true
        if [ -n "$ref" ]; then
            prompt="${prompt}

Reference (from man/--help):
${ref}"
        fi
    fi

    echo "$prompt"
}

# Parse the LLM response into brief and extended parts
parse_response() {
    local response="$1"
    local part="$2"

    if [ "$part" = "brief" ]; then
        echo "$response" | grep '^BRIEF:' | sed 's/^BRIEF:[[:space:]]*//'
    elif [ "$part" = "extended" ]; then
        echo "$response" | sed -n '/^EXTENDED:/,$ p' | sed 's/^EXTENDED:[[:space:]]*//'
    fi
}

# Call Claude to generate an explanation (returns raw response)
generate_explanation() {
    local prompt="$1"
    claude -p "$prompt" 2>/dev/null || echo ""
}

# === Source-only mode ===
if [ "${1:-}" = "--source-only" ]; then
    return 0 2>/dev/null || exit 0
fi

# === Main execution ===

# Read JSON from stdin
INPUT=$(cat)

# Parse with jq — exit silently if jq missing or JSON malformed
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name' 2>/dev/null) || exit 0
[ -z "$TOOL_NAME" ] || [ "$TOOL_NAME" = "null" ] && exit 0

TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty' 2>/dev/null) || exit 0

# --parse-only mode for testing
if [ "${1:-}" = "--parse-only" ]; then
    echo "$TOOL_NAME"
    echo "$TOOL_INPUT"
    exit 0
fi

if [ "${1:-}" = "--normalize-only" ]; then
    normalize "$TOOL_NAME" "$TOOL_INPUT"
    exit 0
fi

# === Main execution ===

# Ensure cache dir exists
mkdir -p "$CACHE_DIR" 2>/dev/null || true

# Run cache cleanup (entries older than 30 days) in background
cache_cleanup &

# Normalize input for cache key
NORMALIZED=$(normalize "$TOOL_NAME" "$TOOL_INPUT") || NORMALIZED=""
KEY=$(cache_key "$NORMALIZED") || KEY=""

# Check cache
CACHED=""
[ -n "$KEY" ] && CACHED=$(cache_lookup "$KEY") || true

BRIEF=""
EXTENDED=""

if [ -n "$CACHED" ]; then
    BRIEF=$(echo "$CACHED" | head -1)
    EXTENDED=$(echo "$CACHED" | tail -n +2)
else
    # Generate explanation via LLM
    PROMPT=$(build_prompt "$TOOL_NAME" "${NORMALIZED#*:}") || PROMPT=""
    RESPONSE=""
    [ -n "$PROMPT" ] && RESPONSE=$(generate_explanation "$PROMPT") || true

    if [ -n "$RESPONSE" ]; then
        BRIEF=$(parse_response "$RESPONSE" "brief") || BRIEF=""
        EXTENDED=$(parse_response "$RESPONSE" "extended") || EXTENDED=""

        # Cache the result
        if [ -n "$BRIEF" ] && [ -n "$KEY" ]; then
            cache_store "$KEY" "${BRIEF}
${EXTENDED}" || true
        fi
    fi
fi

# Output to stderr
if [ -n "$BRIEF" ]; then
    # Header: tool name + brief
    echo "  ◆ ${TOOL_NAME}  ${BRIEF}" >&2

    # Extended explanation (skip if tool is learned)
    if [ -n "$EXTENDED" ] && ! is_learned "$NORMALIZED"; then
        echo "$EXTENDED" | fmt -w 72 | while IFS= read -r line; do
            echo "    $line" >&2
        done
    fi
fi

exit 0
