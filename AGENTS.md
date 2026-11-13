# Downloads and hosting

Never commit `public/DevDock.dmg` or `public/updates/`. GitHub release candidates are built through the manual release workflow. Local website previews serve only a locally built artifact. Set `REQUIRE_DOWNLOAD=1` when packaging a website that promises a bundled DMG; the download checker validates its format and update metadata. No website deployment service or cloud-preview integration is configured. Link `/DevDock.dmg` for a bundled website download or the appropriate GitHub release asset.

# Releases require explicit approval

The hardened branch uses manual production deployment. Never push, open PRs, merge, publish, deploy, upload notarization requests, or change remote settings without the user's explicit approval. Local development builds are ad-hoc artifacts; public releases require complete Developer ID signing and notarization. Do not bump `CFBundleVersion` manually. See `DevDock/UPDATES.md`.

# Verification and scope

Run `scripts/verify.sh` and the relevant focused tests. Live Docker checks must use only fixtures created by `scripts/live-integration.py`; never stop the user's other containers or shared processes. Preserve English-only UI and disabled telemetry. Project manifests and session files are read-only, untrusted inputs.

# Keep the marketing demo in sync with the product

The native macOS app is the source of truth for product UI and behavior. Whenever a change affects a screen, control, label, visual style, or interaction represented on the marketing website, update the website in the **same change**. Do not leave the marketing demo showing an older version of the product.

- Compare `DevDock/Sources/DevDock/UI/` (especially `ServersView.swift`, `ServerDetailView.swift`, `Components.swift`, and `Theme.swift`) with `app/components/App.tsx`, `icons.tsx`, `servers.ts`, and `landing.module.css`.
- Mirror layout, typography, colors, formatting, states, and interactions. Keep demo data deterministic and external/destructive actions simulated; never operate on the visitor's real processes or sessions.
- Update affected marketing copy in `Copy.tsx` and `README.md`, the product overview agents read in `content/devdock.md` (served as `/index.md` and in `/llms.txt`), and any guide in `content/guides/` that describes the changed behavior. Refresh affected product screenshots in `docs/images/` and any referenced product images in `public/` when their depicted UI changes. Do not replace unrelated artwork or rebuild the downloadable app for a demo-only change.
- Verify every affected demo view and interaction in a browser on desktop and mobile, check for console errors, and run `npm run build`. Save review screenshots in `.context/`.
- If a product change has no marketing equivalent, state that briefly in the change description instead of inventing a new marketing screen.

# Guides and agent-readable pages

Articles live in `content/guides/*.md` (frontmatter: `title`, `description`, `published`, `updated`, `order`, `keywords`) and render at `/guides/<slug>`. Every page is also served as Markdown (`/index.md`, `/guides.md`, `/guides/<slug>.md`, or any page with `Accept: text/markdown`), and listed in `/llms.txt`, `/llms-full.txt` and `/sitemap.xml`, all generated from `content/`. Test every shell command in a guide on a Mac before publishing it, and keep claims about DevDock in line with the app's defaults in `Preferences.swift` and `ServerMonitor.swift`.

# Native layout and legal notices

Use system fonts without bundled font binaries. Server-row text must shrink/truncate within the popover, and the hover action slot must keep a constant width. Preserve the layout regression test with stopped containers and long context. The owner's modification copyright belongs in LICENSE; the full required inherited and dependency permission notices belong in THIRD_PARTY_NOTICES.md and must be packaged with the app. Do not remove mandatory notices or reintroduce cloud-provider onboarding.
