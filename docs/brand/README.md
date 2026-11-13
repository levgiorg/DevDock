# DevDock — Midnight identity

Selected by the user: **01 Midnight**, combining minimal developer-tool precision with native macOS polish. The same interlocking dock mark is used in GitHub artwork, app icon, outlined wordmarks, website header and menu-bar template image.

## Final assets

All paths below are relative to `docs/brand/midnight/`:

| File | Use |
|---|---|
| `github-banner.png` | Original generated 2:1 GitHub/README banner |
| `github-social-1280x640.png` | GitHub social preview at 1280 × 640 |
| `app-icon-master.png` | Transparent source artwork for the macOS icon |
| `DevDock.icns` | Complete macOS icon container, including Retina sizes |
| `devdock-logo-light.svg` / `.png` | Transparent outlined logo for light backgrounds |
| `devdock-logo-dark.svg` / `.png` | Transparent outlined logo for dark backgrounds |
| `devdock-mark.svg` / `.png` | Standalone colored symbol |
| `devdock-menubar.svg` / `.png` | Monochrome template symbol |

Palette: midnight `#101827`, blue `#4B8DFF`, teal `#5AE0CA`, white `#F4F7FB`. The menu-bar mark is a template image, so macOS supplies the light/dark foreground automatically. Normal, count and attention states remain supported.

## Generation and production handling

The three concept boards, final app-icon artwork and GitHub banner were created with the built-in `image_gen` tool. [Exact prompts](prompts.json) are preserved. `concepts/01-midnight.png`, `02-amber.png` and `03-monochrome.png` preserve the palette comparison requested by the user.

The generated transparent raster wordmark had visible edge artifacts and was discarded. The final wordmarks are clean SVG outlines, preserved as outlined artwork from the approved design. No external font service, JavaScript or tracking is embedded in the SVGs. The same vector contours generate the AppKit paths and website component. The application and website use system fonts and bundle no font software.

`build-vectors.py` regenerates the mark assets from the approved contours; the wordmark outlines remain frozen artwork. `render-assets.mjs` renders them to transparent PNG with Playwright. The app-icon master is converted to standard icon sizes with macOS `sips` and `iconutil`; it is not cropped or creatively retouched by a script. Original generated files remain preserved.

The app displays **DevDock**, has bundle identity `com.devdock.app` and URL scheme `devdock`, and builds as `DevDock/.build/DevDock.app`. The Swift target and executable are DevDock; `wtp` remains the optional terminal alias. Required copyright and third-party license notices are retained.

Brand assets are included in the source repository. Built DMGs remain ignored local artifacts; publishing releases or deploying the site requires separate approval.
