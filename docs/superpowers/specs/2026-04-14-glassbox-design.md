# glassBox Design Spec

**Date:** 2026-04-14
**Status:** Draft

## Overview

glassBox is a Claude Code hook plugin that provides real-time, human-friendly explanations of every tool Claude uses during a session. It makes Claude Code transparent to non-technical users by describing what each tool does, what its arguments mean, and why it matters — without exposing the user's private data (file paths, URLs, secrets).

## Goals

- Help users understand what Claude Code is doing while it works
- Explain tools and commands in plain English, including flags and argument roles
- Protect privacy by never echoing user-specific values (paths, URLs, branch names, tokens)
- Minimize cost and latency through aggressive caching
- Ship as a distributable, installable plugin with zero runtime dependencies beyond `jq` and the `claude` CLI

## Architecture

### Hook Registration

glassBox registers a single `PreToolUse` hook with matcher `*` (all tools) in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/glassbox.sh"
          }
        ]
      }
    ]
  }
}
```

### Execution Flow

1. Claude is about to use a tool (e.g., `Bash` with `git rebase -i HEAD~3`)
2. Claude Code invokes `glassbox.sh`, passing tool call JSON on stdin:
   ```json
   {
     "tool_name": "Bash",
     "tool_input": {"command": "git rebase -i HEAD~3"},
     "session_id": "abc123"
   }
   ```
3. The script extracts `tool_name` and `tool_input`
4. It normalizes the input to produce a cache key (see Cache Design)
5. It prints a brief one-liner to stderr immediately
6. It checks the cache:
   - **Hit:** prints the cached extended explanation to stderr
   - **Miss:** calls Claude via `claude -p` to generate the explanation, caches it, prints it to stderr
7. Exits 0 (never blocks the tool call)

### Two-Part Output

Every explanation has two parts, both printed to stderr:

- **Brief (line 1):** A one-liner of max 10 words, printed immediately. Example: *"Switching branches in git"*
- **Extended (lines 2+):** A plain-English explanation of the command/tool and its flags/arguments, under 60 words. Printed after cache lookup or LLM call. Example: *"Rebase replays your commits on top of another branch's history, rewriting the commit timeline. The `-i` flag opens an interactive editor where you can reorder, squash, or edit individual commits. `HEAD~3` means it covers the last 3 commits."*

### Visual Formatting

Output uses colored text with indentation — no background fills or box drawing. Hook subprocesses spawned by Claude Code have no TTY and cannot detect terminal width (`tput cols` returns 80 default, `/dev/tty` is unavailable, `$COLUMNS` is 0). Edge-to-edge background highlighting is only possible from Claude Code's own renderer. The output style uses ANSI foreground colors and indentation to visually group explanations.

### Learning (Dismiss Familiar Tools)

Users can mark tools they already understand via `glassbox learn <tool>`. Learned tools show only the brief one-liner, skipping the extended explanation. The learned list is stored in `~/.glassbox/learned` (one tool pattern per line). `glassbox unlearn <tool>` re-enables full explanations. `glassbox learned` lists all dismissed patterns.

## Cache Design

### Cache Key Generation

The cache key is a hash of `tool_name` + a normalized version of `tool_input`.

**Normalization rules:**

- **Bash commands:** Extract the program name and flags. Strip all positional arguments (paths, URLs, file names, branch names, variable values). `git checkout -b my-feature` normalizes to `git checkout -b`. `curl -X POST https://api.example.com/data` normalizes to `curl -X POST`.
- **Non-Bash tools:** Use `tool_name` + parameter keys (not values). Strip all values — file paths, search patterns, content strings. `Read {file_path: "/src/app.tsx", offset: 50, limit: 100}` normalizes to `Read {offset, limit}`. `Grep {pattern: "handleClick", type: "tsx"}` normalizes to `Grep {pattern, type}`. The search pattern value is excluded from the cache key and from the LLM prompt — only the fact that a pattern parameter was provided matters. This means all Grep calls with the same parameter shape share one cached explanation.
- **Secrets stripping:** Any value that looks like an API key, token, or environment variable reference is replaced with a placeholder before hashing and before inclusion in the LLM prompt.

**Hash function:** `echo "<normalized>" | shasum -a 256 | cut -c1-16` — a 16-char hex prefix, sufficient to avoid collisions at this scale.

### Cache Storage

- Location: `~/.glassbox/cache/`
- Format: One file per cache entry, named by the hash
- Content: Plain text — line 1 is the brief, lines 2+ are the extended explanation
- Invalidation: File-age based. Entries older than 30 days are purged via `find ~/.glassbox/cache -mtime +30 -delete`, run at the start of each invocation

## Explanation Generation

On cache miss, glassBox calls Claude via `claude -p` with a structured prompt.

### Base Prompt

```
You are glassBox, explaining Claude Code tools to a non-technical user.

Tool: {tool_name}
Input: {normalized_tool_input}

Respond with exactly two sections:
BRIEF: A one-liner (max 10 words) of what this does.
EXTENDED: A plain-English explanation of the command/tool and its flags/arguments. Do not include specific file paths, URLs, branch names, or user values. Explain what the arguments DO, not what they ARE. Keep it under 60 words.
```

### Bash Command Enrichment

For Bash tool calls, before calling Claude, the script attempts to gather reference material:

1. Extract the base command (e.g., `git` from `git rebase -i HEAD~3`)
2. Try `man <command> 2>/dev/null | head -30` for a synopsis
3. If no man page, try `<command> --help 2>&1 | head -20`
4. If either succeeds, append to the prompt:
   ```
   Reference (from man/--help):
   {synopsis text}
   ```

This grounds the explanation in actual documentation rather than relying solely on the LLM's training data.

### Response Parsing

The LLM response is parsed by looking for `BRIEF:` and `EXTENDED:` prefixes. The brief line is stored as line 1 of the cache file, the extended text as lines 2+.

## Distribution

### Repository Structure

```
glassbox/
├── glassbox.sh          # Main hook script
├── install.sh           # Merges hook into ~/.claude/settings.json
├── uninstall.sh         # Removes hook from settings, optionally deletes cache
└── README.md            # Usage and installation docs
```

### Installation

User clones the repo and runs `./install.sh`, which:

1. Checks for required dependencies (`jq`, `claude`, `shasum`, `man`)
2. Warns (non-fatal) if any are missing
3. Creates `~/.glassbox/cache/` if it doesn't exist
4. Reads `~/.claude/settings.json` (or creates it if absent)
5. Merges a `PreToolUse` hook entry pointing to the absolute path of `glassbox.sh`
6. Makes `glassbox.sh` executable

### Uninstallation

`./uninstall.sh`:

1. Removes the glassBox hook entry from `~/.claude/settings.json`
2. Prompts whether to delete `~/.glassbox/cache/`

### Dependencies

- **Required:** `jq` (JSON parsing), `claude` CLI (LLM calls), `shasum` or `md5` (cache keys)
- **Optional:** `man` (Bash command enrichment — graceful fallback if unavailable)
- **Standard unix tools:** `find`, `head`, `cat`, `echo` (assumed present)

## Privacy & Security

- **No user data in LLM calls.** Paths, URLs, filenames, branch names, secrets, and variable values are stripped during normalization before anything is sent to Claude.
- **No user data in output.** Explanations describe what arguments do, never what they are.
- **Cache is local only.** `~/.glassbox/cache/` is never synced, uploaded, or shared.
- **Never blocks execution.** The script always exits 0. If the LLM call fails, times out, or `jq` is missing, glassBox silently skips — the tool runs regardless.
- **No secrets exposure.** Environment variable references, API keys, and auth tokens are detected and replaced with placeholders during normalization.

## Error Handling

- Missing `jq`: exit 0 silently (tool proceeds, no explanation shown)
- Missing `claude` CLI: print brief from hardcoded fallback descriptions, skip extended explanation
- LLM call timeout/failure: print brief only, skip extended, exit 0
- Malformed stdin JSON: exit 0 silently
- Cache directory missing: attempt to recreate; if that fails, run without caching
