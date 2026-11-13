# Native layout and integration cleanup

The reported screenshots exposed an overflowing minimum width in server rows. The stopped-container message and long control-warning context were forced onto an unshrinkable line. The hover action slot also changed from 40 to 70 points. A parent with a fixed 400-point width could therefore center oversized content and clip both edges.

The row now uses a flexible text column with single-line truncation and full-context tooltips. Stopped-container rows show a concise status. The activity/action slot remains 70 points in both states. Memory text and the legend fit their available width. The website demonstration mirrors the stable slot and stopped status.

The regression test measures rows directly under the actual proposed width, before an outer frame can hide overflow. It covers running/stopped containers, long image/project names, long shared-service warnings, and idle/hover states. The test was run against the original layout and failed with the expected overflow assertions, then passed with the fix. An optional deterministic screenshot fixture contains only fake containers and no private local project data.

Cloud-preview onboarding, settings, lookup endpoints, terminal actions, demo buttons/icons, deployment workflow/configuration and optional related recommendations have been removed. Native and web UI use system fonts; font binaries and their retired license section were removed. Existing logo wordmarks remain outlined artwork and do not embed font software.

The main LICENSE identifies the current owner's modifications. The complete inherited MIT notice is retained in THIRD_PARTY_NOTICES.md, alongside required dependency notices, and is packaged in the application. Optional author branding and promotion are absent.

This cleanup is developed locally on `codex/native-layout-cleanup`. It does not modify the already published prerelease or upload a new release. Native/browser checks and local installation evidence are recorded in the ignored `.context/` directory; completion results are documented in the handoff.

## Verification result

The final native suite passes 86 discovered tests (82 ordinary tests execute; four opt-in live tests skip). Eight desktop/mobile browser tests pass, including a relative-geometry check that the memory column does not move on hover; relative coordinates exclude the demo-opening scale animation. The website production build, dependency audit, repository policy, ShellCheck, Actionlint and font-tool advisory check pass.

Build 13 was installed locally. Before the Mac locked, the actual menu-bar list showed complete port numbers, project headings and memory values; read-only detail/back navigation and the cleaned Integrations pane were observed. No container or local service was started/stopped during these UI checks. Native hover geometry was verified using both states of the actual SwiftUI row; a separate physical-pointer hover check was not completed before the lock. The application and six-step onboarding contain no cloud-preview control.

Private local screenshots and logs stay under `.context/`. Public product screenshots use only deterministic fake containers rendered by the native views. No real local project names are published by these refreshed images.
