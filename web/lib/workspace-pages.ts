import type { WorkspacePageConfig } from "@/components/workspace-page";

const noDataBody =
  "This foundation is intentionally empty until the server gateway is connected. No research records have been fabricated for the web shell.";

export const workspacePages = {
  today: {
    section: "01 / Review",
    title: "Today",
    description: "A quiet place for verified, high-priority research that needs your attention now.",
    columns: ["Priority", "Opportunity", "Evidence", "State"],
    emptyEyebrow: "DATA STATE / NOT CONNECTED",
    emptyTitle: "No verified opportunities yet",
    emptyBody: noDataBody,
  },
  radar: {
    section: "02 / Monitor",
    title: "Live Radar",
    description: "A chronological view of research signals, with source truth attached to every item.",
    columns: ["Detected", "Signal", "Source", "Verification"],
    emptyEyebrow: "DATA STATE / NOT CONNECTED",
    emptyTitle: "Radar is waiting for the first signal",
    emptyBody: noDataBody,
  },
  topics: {
    section: "03 / Organize",
    title: "Topics",
    description: "Server-computed topic groupings for finding patterns without losing their evidence.",
    columns: ["Topic", "Activity", "Evidence", "Last update"],
    emptyEyebrow: "DATA STATE / NOT CONNECTED",
    emptyTitle: "No topic index available",
    emptyBody: noDataBody,
  },
  comments: {
    section: "04 / Listen",
    title: "Comments",
    description: "Audience questions and confusion signals, kept close to their original source and timestamp.",
    columns: ["Question", "Source", "Captured", "Truth"],
    emptyEyebrow: "DATA STATE / NOT CONNECTED",
    emptyTitle: "No comment signals available",
    emptyBody: noDataBody,
  },
  watchlists: {
    section: "05 / Track",
    title: "Watchlists",
    description: "The people, sources, topics, and keywords you have chosen to keep in view.",
    columns: ["Name", "Kind", "Provider", "State"],
    emptyEyebrow: "DATA STATE / NOT CONNECTED",
    emptyTitle: "No watchlists configured",
    emptyBody: noDataBody,
  },
  notifications: {
    section: "06 / Attend",
    title: "Notifications",
    description: "Immediate and digest history with a clear link back to the opportunity that caused it.",
    columns: ["Received", "Reason", "Opportunity", "Read state"],
    emptyEyebrow: "DATA STATE / NOT CONNECTED",
    emptyTitle: "No notification history available",
    emptyBody: noDataBody,
  },
  sources: {
    section: "07 / Verify",
    title: "Sources",
    description: "A source health ledger for collection state, last activity, evidence, and repair ownership.",
    columns: ["Source", "State", "Last activity", "Evidence"],
    emptyEyebrow: "DATA STATE / NOT CONNECTED",
    emptyTitle: "Source health is not available",
    emptyBody: noDataBody,
  },
  settings: {
    section: "08 / Configure",
    title: "Settings",
    description: "Refresh cadence, quiet hours, notifications, locale, and display time zone.",
    columns: ["Preference", "Current value", "Scope", "State"],
    emptyEyebrow: "DATA STATE / NOT CONNECTED",
    emptyTitle: "Preferences are not connected",
    emptyBody: noDataBody,
  },
} satisfies Record<string, WorkspacePageConfig>;
