# Verification evidence

Date: 2026-11-13. Host: Apple Silicon macOS 26.3.1 (25D771280a), Swift 6.2.4 Command Line Tools, Docker Desktop 4.37.1 / Engine 27.4.0. The standalone module rename, product-link changes and export were checked again before the initial push.

The preceding reviewed checkpoint passed 80 ordinary native regression tests, four opt-in real macOS/Docker tests and eight Chromium desktop/mobile checks. Actual menu-bar UI checks covered English under a legacy Chinese preference, native pause/resume/restart/stop, Cancel, Docker stop/start, full-ID confirmations, port mappings, Settings/Privacy, and the selected Midnight icon. No CLI installation, login registration or notification permission was granted. The complete earlier worktree/evidence is preserved separately; it is not fabricated as fresh Git history.

The Docker harness uses a non-root, read-only busybox fixture, loopback-only publication, no host mounts, dropped capabilities, no-new-privileges and CPU/memory limits. Cleanup validates full IDs and a unique label. Only fixtures created by the harness are mutated.

## Standalone validation

| Check | Observed result |
|---|---|
| Native tests | 84 discovered; 80 ordinary tests pass with four opt-in tests skipped. A separate real integration run passes all four opt-in tests. |
| Live fixtures | Native listener pause/resume/stop and restart, read-only Git worktree/Claude fixture metadata, Docker pause/unpause/restart/stop/start; sibling fixtures survive. Harness cleanup leaves no audit containers. |
| Website | Unit/security/resource checks and production build pass; 30 static pages generate. Eight Chromium desktop/mobile tests pass, including maintainer/repository branding. |
| Dependency checks | npm audit reports zero known vulnerabilities. Fresh pip-audit checks find zero in the three hash-locked packaging dependencies and two brand-authoring dependencies. Swift advisory-coverage limits are inherited from the preceding documented review. |
| Static scans | Semgrep security-audit: 100 rules on 159 files, zero findings/errors. Three targeted native rules on 46 files, zero findings/errors. Source-only Gitleaks and the fresh Git history are clean. ShellCheck, policy scan, seven update-config tests and diff checks pass. |
| App and package | Release-optimized DevDock executable/app builds. Strict/deep code-signature verification, arm64, English-only resources, matching packaged legal notices, terminal version and JSON list pass. DevDock DMG builds and hdiutil verification passes. These are ad-hoc, unnotarized local artifacts. |
| Real UI after rename | Native launch, menu-bar list, English General settings and About were observed. About shows George Levis, levgiorg/DevDock issue/repository links, legal-notice buttons and no donation controls. The app was quit afterward. No notification, login or CLI-install permission was granted. |
| Repository | GitHub confirms levgiorg/DevDock is private and is not a fork. The local repository has fresh history and only its own origin. Required license notices remain; an owner modification copyright was added. |

Evidence is ignored under `.context/`: `final-verify.log`, `live-integration.log`, `browser-tests.log`, `app-build.log`, `dmg-build.log`, `bundle-verification.log`, `standalone-about.png`, advisory JSON and scanner JSON/logs. Raw local process metadata is not committed. A broad scan also matched eight generated Next.js preview/cache keys under ignored `.next/`; those are excluded from source. The independent source-only and Git-history scans are clean.

Run:

```sh
npm ci --ignore-scripts
./scripts/verify.sh
npm run test:browser
python3 scripts/live-integration.py
./DevDock/build-app.sh
./DevDock/make-dmg.sh
```

## Not verified

Developer ID signing, notarization/stapling, quarantined downloaded-app launch, signed-update installation, production deployment, Intel/macOS 14, actual alternate Docker daemons, live multi-IP/IPv6 publications, authenticated GitHub preview/PR queries and authenticated agent-session resume. Browser mobile emulation is not physical iPhone/Safari coverage. No release, deployment or notarization upload accompanies the source push.

## Public CI/release preparation checkpoint

The owner subsequently deleted the private remote and authorized recreating `levgiorg/DevDock` publicly. Current local checks pass for the website/native regressions, workflow syntax (Actionlint), shell checks, Go race tests/vet and Go vulnerability audit using Go 1.27.4. Real Linux procfs/listener tests also pass in an isolated non-root, read-only, network-disabled Linux container without access to the developer's Docker daemon socket. The macOS development candidate is version 2.8.0, build 12; its DMG filename explicitly says unnotarized and its checksum verifies. Public GitHub CI and real Linux-host Docker lifecycle results are recorded after the runs finish. No Apple signing/notarization credentials are available, and draft preparation does not constitute approval to publish an unnotarized macOS package.

## Local layout and integration cleanup

See [UI cleanup evidence](UI-CLEANUP.md) for the new native width/hover regression, its expected failure on the prior layout, 86-test native suite, eight browser checks, current system-font UI, removed cloud-preview/deployment integration, and local build-13 installation. This change is local until separately approved for a source push or release update.
