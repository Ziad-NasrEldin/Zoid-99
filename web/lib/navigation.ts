export type NavigationItem = {
  label: string;
  href: string;
  shortLabel: string;
};

export const primaryNavigation: NavigationItem[] = [
  { label: "Today", href: "/today", shortLabel: "Today" },
  { label: "Radar", href: "/radar", shortLabel: "Radar" },
  { label: "Watchlists", href: "/watchlists", shortLabel: "Lists" },
  { label: "Notifications", href: "/notifications", shortLabel: "Alerts" },
];

export const secondaryNavigation: NavigationItem[] = [
  { label: "Topics", href: "/topics", shortLabel: "Topics" },
  { label: "Comments", href: "/comments", shortLabel: "Comments" },
  { label: "Sources", href: "/sources", shortLabel: "Sources" },
  { label: "Settings", href: "/settings", shortLabel: "Settings" },
];

export const allNavigation = [...primaryNavigation, ...secondaryNavigation];
