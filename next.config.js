const fs = require('fs')
const path = require('path')

// CI builds the download into public/ for each production deploy; it's never
// checked in. Local previews serve only the locally built DevDock artifact.
// Production builds cannot run without it (scripts/check-download.mjs).

// The Mac app's version, for the site's structured data (lib/content.ts). CI builds
// with the whole repo; anywhere the app source is missing, the version is left out.
let appVersion = ''
try {
  const plist = fs.readFileSync(path.join(__dirname, 'DevDock/Info.plist'), 'utf8')
  appVersion = plist.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)?.[1] ?? ''
} catch {}

/** @type {import('next').NextConfig} */
const nextConfig = {
  poweredByHeader: false,
  env: { APP_VERSION: appVersion },
  async headers() {
    return [{ source: '/:path*', headers: [
      { key: 'X-Content-Type-Options', value: 'nosniff' },
      { key: 'Referrer-Policy', value: 'no-referrer' },
      { key: 'X-Frame-Options', value: 'DENY' },
      { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=(), payment=(), usb=()' },
      { key: 'Content-Security-Policy', value: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; frame-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'none'" },
    ] }]
  },
  async redirects() {
    // The download was a zip before 2.4. Keep old links working.
    const legacy = { source: '/DevDock.zip', destination: '/DevDock.dmg', permanent: false }
    return [legacy]
  },
}

module.exports = nextConfig
