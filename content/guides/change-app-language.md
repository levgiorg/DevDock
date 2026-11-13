---
title: English interface in DevDock
description: This build uses English throughout while preserving Unicode project names and paths.
published: 2026-11-13
updated: 2026-11-13
order: 11
keywords: English interface, Unicode, language
---

This build uses English in the macOS app, onboarding, Settings, terminal and website. It has no non-English localization tables. System language settings and previously saved preferences cannot change the interface language.

Project names, branches, paths, commands and session titles retain their original Unicode text. Monitored projects are read-only inputs.

The compatibility command `wtp language en` selects English. Other translation codes are rejected. The terminal help and JSON field names also use English.
