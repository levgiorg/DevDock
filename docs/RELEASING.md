# CI, runner billing and releases

GitHub documents standard GitHub-hosted runner compute as free for public repositories: [billing](https://docs.github.com/en/actions/concepts/billing-and-usage) and [standard runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). This repository uses only `ubuntu-24.04`, `ubuntu-24.04-arm` and `macos-26`. It does not select larger paid runners. Storage/cache limits and billing remain separate; release-workflow artifacts retain for seven days. Run timeouts and concurrency cancellation avoid unnecessary work. No scheduled workload or external deployment is enabled.

`CI` runs on main pushes and PRs and can be called by the release workflow. It checks the website and Chromium desktop/mobile demo; dependency, secret and shell policies; macOS Swift tests and app build; and Linux amd64/arm64 Go tests, race detector, vet, Go vulnerability audit, static build and real Docker lifecycle fixtures. PRs have read-only tokens and no signing credentials. The Linux Docker harness is restricted to disposable GitHub runners and only removes full IDs with its nonce label. The local macOS harness remains separate. Linux integration tests can also run in an isolated container without mounting the developer's Docker socket.

## Prepare a candidate

Dispatch **Prepare release** on `main`, with:

- `tag`: a new version such as `v2.8.0-beta.1`.
- `build_number`: numeric and higher than every previously distributed macOS build; the first candidate is `12`, above inherited `11`. Fresh Git commit counts are not used for this workflow.
- `notarize`: off for development candidates; on only after signing credentials are configured and Apple uploads are approved.

The workflow first runs CI, then produces:

- `DevDock-<version>-macos-arm64-unnotarized.dmg`, or `...-notarized.dmg`.
- `DevDock-<version>-linux-amd64.tar.gz`.
- `DevDock-<version>-linux-arm64.tar.gz`.
- `SHA256SUMS` covering all three archives.

It creates a **draft prerelease**, never a public release automatically. Inspect results, assets, checksums and notes before publishing. Experimental macOS packages are ad-hoc signed and not notarized; Gatekeeper can block them. An owner must explicitly authorize the exception before public publication, and labeling must remain accurate. No system-wide security bypass is part of the installer or documentation. A draft is not evidence that a notarized public release exists.

The Linux package is a terminal companion with read-only native process inspection and confirmed local Docker operations. It is not a Linux desktop/tray app or complete macOS feature port. Intel macOS packages are not built by this workflow. Neither platform has an automatic updater configured in these initial packages.

## Optional Apple signing

Configure these repository Secrets through GitHub's secure UI, never in source or chat:

- `DEVELOPER_ID_P12`: base64-encoded Developer ID Application certificate and private key.
- `DEVELOPER_ID_P12_PASSWORD`: certificate export password.
- `NOTARY_API_KEY`: Apple notarization API private key contents.
- `NOTARY_API_KEY_ID` and `NOTARY_API_ISSUER_ID`.

The job creates a temporary keychain, enables hardened runtime for Developer ID builds, signs nested components from the inside out, uploads for Apple notarization, staples tickets, verifies the bundle and DMG, then removes credentials even on failure. These signing/notary branches are untested without credentials. The source owner authorized preparing a development candidate, not a fabricated signing identity. The existing separately configured Sparkle/Vercel deployment workflow remains manual and is not invoked for a GitHub release.
