#!/bin/bash
# install.sh — register glassBox as a Claude Code hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GLASSBOX_SCRIPT="${SCRIPT_DIR}/glassbox.sh"
GLASSBOX_CLI="${SCRIPT_DIR}/glassbox"
SETTINGS_FILE="${HOME}/.claude/settings.json"
GLASSBOX_DIR="${HOME}/.glassbox"

echo "Installing glassBox..."

# Check dependencies
for cmd in jq claude shasum; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "  Warning: '$cmd' not found. glassBox needs it at runtime."
    fi
done

# Make scripts executable
chmod +x "$GLASSBOX_SCRIPT"
chmod +x "$GLASSBOX_CLI"

# Create cache directory
mkdir -p "${GLASSBOX_DIR}/cache"
echo "  Created ${GLASSBOX_DIR}/cache"

# Add to PATH hint
echo "  To use 'glassbox' CLI, add to your PATH:"
echo "    export PATH=\"${SCRIPT_DIR}:\$PATH\""

# Merge hook into settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo '{}' > "$SETTINGS_FILE"
fi

# Check if hook already registered
if jq -e '.hooks.PreToolUse[]? | select(.hooks[]?.command == "'"$GLASSBOX_SCRIPT"'")' "$SETTINGS_FILE" &>/dev/null; then
    echo "  Hook already registered."
else
    # Add the PreToolUse hook
    UPDATED=$(jq --arg cmd "$GLASSBOX_SCRIPT" '
        .hooks.PreToolUse = (.hooks.PreToolUse // []) + [{
            "matcher": "*",
            "hooks": [{
                "type": "command",
                "command": $cmd
            }]
        }]
    ' "$SETTINGS_FILE")
    echo "$UPDATED" > "$SETTINGS_FILE"
    echo "  Registered PreToolUse hook in ${SETTINGS_FILE}"
fi

echo ""
echo "glassBox installed. Restart Claude Code to activate."
