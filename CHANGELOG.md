# Changelog

All notable changes to glassBox are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Suppress repeat explanations within a session, so the same tool/input pair is explained once per Claude Code session (2026-04-15).

### Fixed
- Emit `systemMessage` JSON and add framed ANSI formatting for hook output (2026-04-14).

### Documentation
- Add `glassBox-in-action` screenshot to README (2026-04-14).
- Rewrite README for public release and add LICENSE (2026-04-14).

## [0.1.0] — 2026-04-14

### Added
- Initial release of glassBox — a Claude Code `PreToolUse` hook that explains every tool call in plain English, with local caching and a "learn" command to dismiss extended explanations.
