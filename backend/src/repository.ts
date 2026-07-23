import type {
  BootstrapPayload,
  NotificationRecord,
  Opportunity,
  OpportunityDisposition,
  ResearchBatch,
  SourceHealth,
  WatchlistEntry,
} from "./domain.js";

export interface ResearchRepository {
  ping(): Promise<void>;
  upsertSourceHealth(health: SourceHealth): Promise<SourceHealth>;
  persistResearchBatch(batch: ResearchBatch): Promise<Opportunity>;
  bootstrap(): Promise<BootstrapPayload>;
  listSourceHealth(): Promise<SourceHealth[]>;
  listOpportunities(disposition?: OpportunityDisposition): Promise<Opportunity[]>;
  getOpportunity(id: string): Promise<Opportunity | null>;
  updateOpportunityDisposition(id: string, disposition: OpportunityDisposition): Promise<Opportunity | null>;
  listWatchlist(): Promise<WatchlistEntry[]>;
  createWatchlist(input: Omit<WatchlistEntry, "id">): Promise<WatchlistEntry>;
  deleteWatchlist(id: string): Promise<boolean>;
  listNotifications(): Promise<NotificationRecord[]>;
  markNotificationRead(id: string, isRead: boolean): Promise<NotificationRecord | null>;
}

export interface EncryptedConfigStore {
  set(key: string, encryptedValue: string): Promise<void>;
  get(key: string): Promise<string | null>;
}
