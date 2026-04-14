#!/bin/bash
# uninstall.sh — remove glassBox hook from Claude Code
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GLASSBOX_SCRIPT="${SCRIPT_DIR}/glassbox.sh"
SETTINGS_FILE="${HOME}/.claude/settings.json"
GLASSBOX_DIR="${HOME}/.glassbox"

echo "Uninstalling glassBox..."

# Remove hook from settings.json
if [ -f "$SETTINGS_FILE" ]; then
    UPDATED=$(jq --arg cmd "$GLASSBOX_SCRIPT" '
        .hooks.PreToolUse = [.hooks.PreToolUse[]? | select(.hooks | all(.command != $cmd))]
        | if .hooks.PreToolUse == [] then del(.hooks.PreToolUse) else . end
    ' "$SETTINGS_FILE")
    echo "$UPDATED" > "$SETTINGS_FILE"
    echo "  Removed hook from ${SETTINGS_FILE}"
fi

# Ask about cache
if [ -d "$GLASSBOX_DIR" ]; then
    read -p "  Delete cache and learned data (~/.glassbox)? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$GLASSBOX_DIR"
        echo "  Deleted ${GLASSBOX_DIR}"
    else
        echo "  Kept ${GLASSBOX_DIR}"
    fi
fi

echo ""
echo "glassBox uninstalled."
