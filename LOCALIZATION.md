# English interface

This build uses English in the native menu bar app, onboarding, Settings, terminal, documentation and marketing demo. All non-English resource tables have been removed. Previously saved language preferences and system language settings cannot switch the interface away from English. `wtp language en` remains supported; other translation codes are rejected.

User data is preserved: project names, file paths, Git branches and session titles retain their original Unicode text. English-only UI does not mean renaming files or altering monitored projects.

Run `swift test` in `DevDock` and `npm test` at the root to verify these boundaries.
