# DevDock security review

Review date: 2026-11-13. Maintainer: George Levis. Repository: `levgiorg/DevDock` (private, standalone). The exported repository starts with fresh Git history. The full earlier source-review worktree and machine-local evidence remain preserved separately on the development host.

No intentional malicious behavior was identified in the reviewed native application, website, scripts or workflows. This is a source review, scanner results, regression tests and controlled integration checks; it is not proof of complete security or a formal audit of every toolchain, operating-system or dependency byte.

## Implemented safeguards

| Area | Behavior |
|---|---|
| Process control | Signal only the freshly verified listener. Require current-user ownership, exact PID start time, matching executable/directory and unambiguous port ownership. Refuse protected processes, embedded infrastructure, agents, shared ports and multi-port listeners. Refresh checks before delayed force-quit and confirm exit before restart. |
| Restart | Execute intact executable argv directly. Reject reconstructed process titles and shell commands. Do not source shell startup files or write predictable process-output logs. Refuse an already occupied port. |
| Stale UI actions | Include process birth time or Docker runtime/full ID in action identity. Preserve it through selections and notification actions. Confirm exact targets and show action failures. |
| Files and sessions | Treat manifests/session metadata as untrusted, read-only inputs. Bound regular-file reads, reject FIFOs and symlinks, cap enumeration, validate session UUIDs and use private unique launch scripts. |
| Docker | Discover only known local Unix sockets. Enforce socket ownership, endpoint allowlists, deadlines, bounded output, strict HTTP framing and full IDs. Refresh identity, state and mappings before start/stop/restart/pause/unpause. Use bounded polling and constrained stats concurrency. |
| Discovery | Scan ports 1–65535 by default. Discover recognized-project executables with application-specific names. Preserve explicit custom filters and exclude other users' processes and desktop infrastructure. |
| Privacy | No native telemetry transport/queue or website analytics. No automatic GitHub-star request. Cleanup supports Off/Ask; unattended termination is disabled. Notifications and login items require user action. Automatic updater checks/downloads default to off. |
| Web | Updated and locked dependencies; sanitized Markdown with attack-payload tests. CSP, MIME, framing, referrer and browser-permission headers. No external font service or unsolicited third-party requests in browser tests. |
| Installation | Optional CLI symlink only under the user's ~/.local/bin. No elevation, privileged daemon or existing-command overwrite. Reject unsafe/symlinked installation directories. |
| Packaging | English-only resources, license notices included, strict signature verification and hash-locked DMG tooling. Developer ID releases require hardened runtime and notarization. Deploy workflow is manual; no release or deployment is authorized by an ordinary source push. |
| Standalone product | Native target/executable and source directory are DevDock. Product links use the maintainer's repository. Personal promotion, donation reminders/payment redirects and obsolete payment pages were removed. Required copyright/license notices and third-party dependencies remain intact. |

## Permissions and external activity

The app is not App Sandbox enabled because process inspection and Docker control need broader local access. It requests no root helper, Full Disk Access or Accessibility entitlement. Global hotkeys use Carbon. Login-item registration and notification permission follow user action.

Known local Docker sockets are used only when discovery is enabled. Socket access has substantial daemon authority even though this client restricts its endpoints. Remote TCP/SSH Docker contexts are not followed. Optional GitHub previews/PRs use the user's installed authenticated gh CLI; they default to off. Browser/editor/terminal links require user selection. Feedback opens the private DevDock issue form and sends nothing until the user submits it. No public website or payment destination is configured.

Configured updater-enabled builds may contact their HTTPS signed update feed; local builds have no feed. Public dependency registries and advisory services are contacted by build/audit tooling. No signing secrets or local fixture data are committed. License notices are preserved in LICENSE and THIRD_PARTY_NOTICES.md.

## Remaining risks and limits

- macOS signals use PIDs: validation and signal delivery cannot be made atomic by this implementation. It fails closed on observed uncertainty; a compromised OS or same-user attacker remains outside its trust boundary.
- Only the listener is signaled. Supervisors may restart it and non-listening workers may remain. Shared/ambiguous services should be managed from their original terminal.
- Rows are port-centric. Ambiguous same-port containers are omitted, and stopped ephemeral/unpublished bindings cannot always be represented. Docker state can briefly lag after mutations.
- Agent/session attribution is a read-only heuristic, not authenticated ownership proof. Authenticated agent resume and authenticated GitHub lookups were not exercised.
- Real integration coverage is Apple Silicon macOS 26 with Docker Desktop. Intel, macOS 14, actual alternate runtimes, live multi-IP/IPv6 publications and Safari/physical mobile devices were not tested.
- Local app/DMG artifacts are ad-hoc and not notarized. Developer ID distribution, quarantine/Gatekeeper release behavior, stapling and signed-update installation were not verified. Development signing omits hardened runtime for ad-hoc Sparkle compatibility; Developer ID builds retain it.
- CSP retains inline script/style support for static Next.js hydration. Swift scanner coverage is incomplete; targeted review and tests complement it. Binary image/icon files are outside text scanning.
- Zero reported advisories/findings is time-limited evidence, not a guarantee against future vulnerabilities or dependency compromise. Required GitHub production reviewers and release version numbering for the fresh history must be configured before the first separately approved release. The inherited build number must not be downgraded by a new history counter.

See [verification](VERIFICATION.md) for commands, observed results and exclusions. The source inventory hashes this standalone export and excludes ignored build/test data and the inventory itself.
