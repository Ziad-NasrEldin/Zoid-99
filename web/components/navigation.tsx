import React from "react";
import Link from "next/link";
import {
  Bell,
  LayoutDashboard,
  ListChecks,
  MessageCircle,
  Radar,
  RadioTower,
  Settings as SettingsIcon,
  Tags,
  type LucideIcon,
} from "lucide-react";

import type { NavigationItem } from "@/lib/navigation";

type NavigationLinksProps = {
  items: NavigationItem[];
  currentPath: string;
  onNavigate?: () => void;
};

const iconByHref: Record<string, LucideIcon> = {
  "/today": LayoutDashboard,
  "/radar": Radar,
  "/watchlists": ListChecks,
  "/notifications": Bell,
  "/topics": Tags,
  "/comments": MessageCircle,
  "/sources": RadioTower,
  "/settings": SettingsIcon,
};

export function NavigationLinks({ items, currentPath, onNavigate }: NavigationLinksProps) {
  return (
    <ul className="navigation-list">
      {items.map((item) => {
        const isCurrent = currentPath === item.href || currentPath.startsWith(`${item.href}/`);
        const Icon = iconByHref[item.href];

        return (
          <li key={item.href}>
            <Link
              className={`navigation-link${isCurrent ? " is-current" : ""}`}
              href={item.href}
              aria-current={isCurrent ? "page" : undefined}
              onClick={onNavigate}
            >
              <Icon aria-hidden="true" className="navigation-icon" size={16} strokeWidth={1.6} />
              <span>{item.label}</span>
            </Link>
          </li>
        );
      })}
    </ul>
  );
}

export function MobileNavigation({ items, currentPath }: NavigationLinksProps) {
  return (
    <nav className="mobile-bottom-nav" aria-label="Primary mobile navigation">
      <NavigationLinks items={items} currentPath={currentPath} />
    </nav>
  );
}
