#!/bin/bash
# glassBox demo — simulates what the hook output looks like in a terminal session

COLS=$(tput cols 2>/dev/null || echo 80)
TEXT_W=$((COLS - 6))

BG='\033[48;2;97;214;253m'
BG_HEAD='\033[48;2;75;190;230m'
FG='\033[38;2;20;20;20m'
FG_DIM='\033[38;2;40;70;90m'
FG_GREEN='\033[38;2;15;100;50m'
BOLD='\033[1m'
NOBOLD='\033[22m'
RESET='\033[0m'
DIM='\033[2m'

# Print a full-width highlighted line by calculating visible width and padding
hl() {
    local bg="$1"; shift
    local text="  $*"
    # Strip ANSI codes to measure visible width
    local stripped
    stripped=$(printf '%b' "$text" | sed $'s/\033\[[0-9;]*m//g')
    local vlen=${#stripped}
    local pad=$((COLS - vlen - 1))
    [ "$pad" -lt 0 ] && pad=0
    printf "${bg}${FG}%b%${pad}s${RESET}\n" "$text" ""
}

show_tool() {
    local icon="$1" tool="$2" brief="$3" extended="$4" detail="$5" result="$6"
    echo ""
    hl "$BG_HEAD" "${icon} ${BOLD}${tool}${NOBOLD}  ${brief}"
    echo "$extended" | fmt -w "$TEXT_W" | while IFS= read -r line; do
        hl "$BG" "  ${FG_DIM}${line}"
    done
    hl "$BG" ""
    hl "$BG" "  ${BOLD}${detail}${NOBOLD}"
    hl "$BG" "  ${FG_GREEN}✓ ${result}"
}

show_tool_brief() {
    local icon="$1" tool="$2" brief="$3" detail="$4" result="$5"
    echo ""
    hl "$BG_HEAD" "${icon} ${BOLD}${tool}${NOBOLD}  ${brief}"
    hl "$BG" "  ${FG_GREEN}✓ ${result}"
}

clear
echo ""
echo -e "${BOLD}  glassBox${RESET} — what you'd see during a Claude Code session"
echo ""
echo -e "  ${DIM}You asked:${RESET} ${BOLD}Fix the login bug in auth.ts${RESET}"

show_tool "🔍" "Grep" \
    "Searching file contents" \
    "Grep scans files using a regular expression. The type flag limits the search to a specific file extension, so only relevant files are checked. Results show file paths and matching lines." \
    "pattern: \"handleLogin\"  type: \"ts\"" \
    "Found 3 matches in 2 files"

show_tool "📖" "Read" \
    "Reading a file from disk" \
    "Read loads a file's contents so Claude can examine it. The offset and limit parameters select a specific range of lines instead of loading the whole file — useful for large files where only one section matters." \
    "src/auth.ts (lines 42-98)" \
    "Done — 56 lines"

show_tool "⚡" "Bash" \
    "Running TypeScript type checker" \
    "npx runs a locally installed package without global install. tsc is the TypeScript compiler. The --noEmit flag checks types without producing output files — a quick way to verify code correctness without a full build." \
    "npx tsc --noEmit" \
    "Exit 0 — no type errors"

echo ""
echo -e "  ${BOLD}After you've marked Grep and Read as \"learned\":${RESET}"

show_tool_brief "🔍" "Grep" \
    "Searching file contents" \
    "pattern: \"handleLogin\"  type: \"ts\"" \
    "Found 3 matches in 2 files"

show_tool_brief "📖" "Read" \
    "Reading a file from disk" \
    "src/auth.ts (lines 42-98)" \
    "Done — 56 lines"

show_tool "✏️" "Edit" \
    "Replacing text in a file" \
    "Edit performs a find-and-replace within a single file. It matches an exact string and swaps it for new content. The replacement must target a unique string — if multiple matches exist, it fails to prevent unintended changes." \
    "src/auth.ts" \
    "Done — file updated"

echo ""
echo -e "  ${BOLD}Learned tools${RESET} show only the brief + result."
echo -e "  New tools still get the full explanation."
echo -e "  Run ${DIM}glassbox learn <tool>${RESET} to dismiss a tool."
echo ""
