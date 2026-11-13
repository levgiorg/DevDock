# Release configuration and update policy

DevDock local source builds have no update feed by default. Automatic checks and downloads are off. Configured Sparkle builds require an HTTPS feed, Ed25519 public key, signed feed and update archive, and signature verification before extraction. Sparkle is pinned in Package.resolved.

Publishing a source update does not authorize deployment or notarization uploads. The owner separately authorized recreating the public repository and preparing a macOS/Linux release. The workflow is manual-only and targets the production environment. Configure required environment reviewers in GitHub before any future use; local source changes cannot enforce repository-side reviewer settings.

## Development builds

Run `./build-app.sh` with no signing variables to build an ad-hoc development app. macOS library validation cannot load separately ad-hoc-signed Sparkle into a hardened app, so development signing intentionally omits hardened runtime. It adds no library-validation exception entitlement. This is not a notarized or redistributable release. Bundle signatures are still verified.

Build scripts do not automatically source `update-config.env` or execute its contents. Export reviewed public configuration explicitly. `update-config.env.example` describes the variables. Private keys belong in Keychain or an approved secret store, never in a repository.

## GitHub release candidates

See [release workflow](../.github/workflows/release.yml) and [release guide](../docs/RELEASING.md). `--distribution` requires Developer ID signing but allows a standalone notarized DMG without configuring Sparkle. `--release` continues to require the signed updater feed. `scripts/package-macos.sh` prepares either a development DMG or explicitly requested notarized artifact; it never publishes. The workflow produces a draft for review. An unnotarized development DMG requires an explicit owner exception before public prerelease publication; it must never be presented as notarized.

## Approved releases

A release requires a Developer ID Application identity, hardened runtime, HTTPS signed feed, Ed25519 key, numeric version/build metadata and notarization credentials. `release.sh` refuses ad-hoc signing and missing notarization. Its notarization steps upload artifacts to Apple and must only be run after explicit authorization.

The manual GitHub workflow requires all signing secrets, notary credentials, Sparkle key material and Vercel deployment credentials. It uses pinned action commits and read-only repository permissions, runs checks before publishing and refuses missing credentials. No ad-hoc fallback is published. Sparkle helpers are signed from the inside out; `codesign --deep` is used for verification only.

Before distribution, verify Developer ID identity, hardened runtime, entitlements, notarization acceptance, stapled tickets, DMG integrity, signed feed/archive and a quarantined clean-machine launch. These release gates were not exercised by the local audit. DevDock has its own bundle identity and requires independently managed feed and signing keys.

## Privacy

Telemetry and website analytics have been removed. Update configuration cannot enable usage reporting. GitHub lookups remain optional and off by default. External links are user-initiated. Third-party license notices are packaged with the app.
