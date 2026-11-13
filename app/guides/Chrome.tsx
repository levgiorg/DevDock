'use client'

import { DevDockLogo } from '../components/DevDockLogo'

import { useEffect, useRef, useState } from 'react'
import styles from './guides.module.css'
import { AppPopover, useDemo } from '../components/App'
import { AppleIcon } from '../components/icons'
import { DOWNLOAD_URL, GITHUB_URL } from '../components/sections'

// Header and footer for the written pages, with the same download tracking as the landing page.

export function DownloadButton({ location }: { location: string }) {
  return (
    <a className={styles.download} href={DOWNLOAD_URL} download>
      <AppleIcon />
      <span>
        Download<span className={styles.forMac}> for macOS</span>
      </span>
    </a>
  )
}

// Downloads linked from inside an article's Markdown.
// The landing page's working popover, dropped down from the header, with sample servers.
function DemoPopover() {
  const demo = useDemo(0)
  return <AppPopover demo={demo} />
}

function TryIt() {
  const [open, setOpen] = useState(false)
  // Mounted on first open, then kept so the demo remembers what you stopped.
  const [mounted, setMounted] = useState(false)
  const [zoom, setZoom] = useState(1)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const fit = () => setZoom(Math.min(1, (window.innerWidth - 32) / 400))
    const onPointer = (event: PointerEvent) => {
      if (!ref.current?.contains(event.target as Node)) setOpen(false)
    }
    const onKey = (event: KeyboardEvent) => event.key === 'Escape' && setOpen(false)
    fit()
    window.addEventListener('resize', fit)
    document.addEventListener('pointerdown', onPointer)
    document.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('resize', fit)
      document.removeEventListener('pointerdown', onPointer)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  const toggle = () => {
    setMounted(true)
    setOpen(!open)
  }

  return (
    <div ref={ref} className={styles.tryIt}>
      <button type="button" className={styles.tryButton} onClick={toggle} aria-expanded={open} aria-controls="demo-popover">
        Try DevDock
      </button>
      <div id="demo-popover" className={styles.demoPanel} data-open={open} role="dialog" aria-label="DevDock demo">
        <p className={styles.demoLabel}>
          <span className={styles.demoBadge}>Demo</span>
          Sample servers, not your Mac. Nothing here touches real processes.
        </p>
        <div className={styles.demoApp} style={{ zoom }}>
          {mounted && <DemoPopover />}
        </div>
      </div>
    </div>
  )
}

export function Header() {
  return (
    <header className={styles.headerBar}>
      <div className={styles.header}>
        <a className={styles.brand} href="/">
          <DevDockLogo size={22} />
          DevDock
        </a>
        <nav className={styles.nav} aria-label="Main">
          <a className={styles.navLink} href="/guides">
            Guides
          </a>
          <a className={styles.navLink} href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
            GitHub
          </a>
          <TryIt />
          <DownloadButton location="guides-header" />
        </nav>
      </div>
    </header>
  )
}

export function Footer() {
  return (
    <footer className={styles.footer}>
      <div className={styles.footerInner}>
        <span className={styles.footerBrand}>
          <DevDockLogo size={18} />
          DevDock
        </span>
        <span className={styles.footerMeta}>DevDock · Maintained by George Levis</span>
        <nav className={styles.footerLinks} aria-label="Footer">
          <a href="/">Home</a>
          <a href="/guides">Guides</a>
          <a href={DOWNLOAD_URL} download>
            Download
          </a>
          <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
            GitHub <span aria-hidden="true">↗</span>
          </a>
        </nav>
      </div>
    </footer>
  )
}
