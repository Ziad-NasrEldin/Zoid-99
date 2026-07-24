export const sourceGroups = [
  "YouTube",
  "Google Trends",
  "Instagram",
  "Comments",
  "US & Official",
  "X",
] as const;

export type SourceGroup = (typeof sourceGroups)[number];
export type VerificationState = "Confirmed" | "Disputed" | "Unverified";
export type ConnectionState =
  | "Connected"
  | "Setup required"
  | "Disconnected"
  | "Unavailable"
  | "Rate limited"
  | "Delayed"
  | "Cached"
  | "Unsupported";
export type OpportunityDisposition = "active" | "saved" | "watched" | "dismissed" | "muted";
export interface OpportunityDispositionMutation {
  disposition: OpportunityDisposition;
  changedAt: string;
  mutationID: string;
}

export interface OpportunityDispositionState extends OpportunityDispositionMutation {
  opportunityID: string;
  outcome: "applied" | "idempotent" | "superseded";
}
export type NotificationDelivery = "Immediate" | "Digest";

export interface SourceHealth {
  group: SourceGroup;
  state: ConnectionState;
  lastActivity: string | null;
  evidence: string;
  repairAction: string;
  dataTruth: "Live" | "Cached" | "Missing" | "Delayed" | "Unavailable" | "Rate limited";
}

export interface SourceItem {
  id: string;
  group: SourceGroup;
  externalID: string;
  title: string;
  summary: string;
  author: string;
  url: string;
  publishedAt: string;
  collectedAt: string;
  language: string;
  country: string;
  topicKey: string;
  isOriginalSource: boolean;
  credibility: number;
  engagement: number;
  verification: VerificationState;
}

export interface ScoreBreakdown {
  freshness: number;
  credibility: number;
  momentum: number;
  creatorActivity: number;
  arabicCoverageGap: number;
  regionalRelevance: number;
}

export interface Opportunity {
  id: string;
  topicKey: string;
  title: string;
  brief: string;
  verification: VerificationState;
  earliestPublishedAt: string;
  originalSource: SourceItem | null;
  items: SourceItem[];
  score: ScoreBreakdown;
  regionalExplanation: string;
  coverageExplanation: string;
  disposition: OpportunityDisposition;
  dispositionUpdatedAt: string;
  dispositionMutationID: string | null;
  isHighPriority: boolean;
}

export interface WatchlistEntry {
  id: string;
  kind: "Creator" | "Official source" | "Company" | "Keyword" | "Topic" | "Country" | "Language";
  value: string;
  highPriority: boolean;
}

export interface NotificationRecord {
  id: string;
  opportunityID: string;
  title: string;
  delivery: NotificationDelivery;
  createdAt: string;
  isRead: boolean;
}

export interface BootstrapPayload {
  sourceHealth: SourceHealth[];
  opportunities: Opportunity[];
  watchlist: WatchlistEntry[];
  notifications: NotificationRecord[];
}

export interface ResearchBatch {
  clusterKey: string;
  topicKey: string;
  verification: VerificationState;
  originState: "Identified" | "Unknown";
  originalSource: Pick<SourceItem, "group" | "externalID"> | null;
  sourceItems: Array<Omit<SourceItem, "id">>;
  opportunity: Omit<
    Opportunity,
    "id" | "topicKey" | "verification" | "earliestPublishedAt" | "originalSource" | "items"
      | "dispositionUpdatedAt" | "dispositionMutationID" | "isHighPriority"
  >;
  notification: Omit<NotificationRecord, "id" | "opportunityID"> | null;
}

export interface IngestionPayload {
  sourceHealth: SourceHealth[];
  batches: ResearchBatch[];
}
