"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import React from "react";
import { useState } from "react";
import { Menu, X } from "lucide-react";

import { AgentationToolbar } from "@/components/agentation-toolbar";
import { LogoutButton } from "@/components/logout-button";
import { MobileNavigation, NavigationLinks } from "@/components/navigation";
import { webApiVersion } from "@/lib/contracts";
import { primaryNavigation, secondaryNavigation } from "@/lib/navigation";

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname() ?? "/today";
  const [isMoreOpen, setIsMoreOpen] = useState(false);

  if (pathname === "/login") {
    return <>{children}</>;
  }

  return (
    <>
      <a className="skip-link" href="#main-content">
        Skip to main content
      </a>
      <div className="app-shell">
        <aside className="desktop-rail" aria-label="Zoid 99 workspace navigation">
          <div className="brand-lockup">
            <Link className="brand-mark" href="/today" aria-label="Zoid 99 home">
              Z99
            </Link>
            <div>
              <p className="brand-name">Zoid 99</p>
              <p className="brand-caption">Research ledger</p>
            </div>
          </div>

          <div className="rail-section">
            <p className="rail-label">Review</p>
            <NavigationLinks items={primaryNavigation} currentPath={pathname} />
          </div>
          <div className="rail-section">
            <p className="rail-label">Workspace</p>
            <NavigationLinks items={secondaryNavigation} currentPath={pathname} />
          </div>

          <div className="rail-footer" aria-label="Web shell status">
            <span className="status-dot" aria-hidden="true" />
            <span>Private workspace</span>
            <span className="muted">Gateway status appears in each view</span>
            <LogoutButton />
          </div>
        </aside>

        <main className="main-column" id="main-content">
          <header className="mobile-topbar">
            <Link className="mobile-brand" href="/today" aria-label="Zoid 99 home">
              Z99 <span>Research ledger</span>
            </Link>
            <button
              className="menu-button"
              type="button"
              aria-expanded={isMoreOpen}
              aria-controls="more-navigation"
              aria-label={isMoreOpen ? "Close more destinations" : "Open more destinations"}
              title={isMoreOpen ? "Close more destinations" : "Open more destinations"}
              onClick={() => setIsMoreOpen((open) => !open)}
            >
              {isMoreOpen ? <X aria-hidden="true" size={16} strokeWidth={1.6} /> : <Menu aria-hidden="true" size={16} strokeWidth={1.6} />}
              <span>{isMoreOpen ? "Close" : "More"}</span>
            </button>
          </header>

          {isMoreOpen ? (
            <nav className="more-navigation" id="more-navigation" aria-label="More destinations">
              <div className="more-navigation-heading">
                <span>Workspace</span>
                <button
                  className="close-menu"
                  type="button"
                  aria-label="Close more destinations"
                  title="Close more destinations"
                  onClick={() => setIsMoreOpen(false)}
                >
                  <X aria-hidden="true" size={16} strokeWidth={1.6} />
                  <span>Close</span>
                </button>
              </div>
              <NavigationLinks
                items={secondaryNavigation}
                currentPath={pathname}
                onNavigate={() => setIsMoreOpen(false)}
              />
              <LogoutButton compact />
            </nav>
          ) : null}

          <div className="shell-status" role="status" aria-live="polite">
            <span className="status-label">PRIVATE RESEARCH WORKSPACE</span>
            <span>API {webApiVersion}</span>
            <span>Gateway-backed research data appears here when available.</span>
          </div>
          {children}
        </main>

        <MobileNavigation items={primaryNavigation} currentPath={pathname} />
      </div>
      <AgentationToolbar />
    </>
  );
}
