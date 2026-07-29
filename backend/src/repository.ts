import type {
  BootstrapPayload,
  CommentProjection,
  CommentsAvailability,
  NotificationRecord,
  NotificationReadQuery,
  Opportunity,
  OpportunityReadQuery,
  OpportunityDisposition,
  OpportunityDispositionMutation,
  OpportunityDispositionState,
  Preferences,
  PreferencesPatch,
  ResearchBatch,
  SourceHealth,
  Topic,
  TopicDetail,
  TopicReadQuery,
  WatchlistEntry,
} from "./domain.js";

export interface ReadPage<T> {
  items: T[];
  nextCursor: string | null;
}

export class InvalidReadCursorError extends Error {
  readonly code = "invalid_cursor";

  constructor() {
    super("The pagination cursor is invalid or does not match this query");
    this.name = "InvalidReadCursorError";
  }
}

export type IdempotencyRecord = {
  requestHash: string;
  statusCode: number;
  responseBody: unknown;
  responseHeaders?: Record<string, string>;
};

export type PreferenceRecord = Preferences & { etag: string };
export type PreferenceUpdate =
  | { outcome: "updated"; current: PreferenceRecord }
  | { outcome: "conflict"; current: PreferenceRecord };

export type ReadCursor = {
  kind: "opportunity" | "notification" | "topic";
  sort: string;
  primary: number;
  secondary: number;
  tertiary?: number;
  timestamp?: string;
  id: string;
};

export function encodeReadCursor(cursor: ReadCursor): string {
  return Buffer.from(JSON.stringify(cursor), "utf8").toString("base64url");
}

export function decodeReadCursor(value: string, kind: ReadCursor["kind"], sort: string): ReadCursor {
  try {
    const decoded = JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as Partial<ReadCursor>;
    if (
      decoded.kind !== kind
      || decoded.sort !== sort
      || typeof decoded.primary !== "number"
      || !Number.isFinite(decoded.primary)
      || typeof decoded.secondary !== "number"
      || !Number.isFinite(decoded.secondary)
      || (decoded.tertiary !== undefined && (typeof decoded.tertiary !== "number" || !Number.isFinite(decoded.tertiary)))
      || typeof decoded.id !== "string"
      || decoded.id.length === 0
      || typeof decoded.timestamp !== "string"
      || Number.isNaN(Date.parse(decoded.timestamp))
    ) throw new Error("invalid");
    return decoded as ReadCursor;
  } catch {
    throw new InvalidReadCursorError();
  }
}

export interface ResearchRepository {
  ping(): Promise<void>;
  createOperatorSession(tokenHash: string, expiresAt: Date): Promise<void>;
  isOperatorSessionValid(tokenHash: string, observedAt: Date): Promise<boolean>;
  deleteOperatorSession(tokenHash: string): Promise<void>;
  syncCursor(): Promise<string>;
  upsertSourceHealth(health: SourceHealth): Promise<SourceHealth>;
  persistResearchBatch(batch: ResearchBatch): Promise<Opportunity>;
  bootstrap(): Promise<BootstrapPayload>;
  listSourceHealth(): Promise<SourceHealth[]>;
  listOpportunities(disposition?: OpportunityDisposition): Promise<Opportunity[]>;
  listOpportunitiesPage(query: OpportunityReadQuery): Promise<ReadPage<Opportunity>>;
  getOpportunity(id: string): Promise<Opportunity | null>;
  updateOpportunityDisposition(
    id: string,
    mutation: OpportunityDispositionMutation,
  ): Promise<OpportunityDispositionState | null>;
  getPreferences(): Promise<PreferenceRecord>;
  updatePreferences(patch: PreferencesPatch, expectedETag: string): Promise<PreferenceUpdate>;
  withIdempotencyLock<T>(scope: string, key: string, operation: () => Promise<T>): Promise<T>;
  getIdempotencyRecord(scope: string, key: string): Promise<IdempotencyRecord | null>;
  saveIdempotencyRecord(scope: string, key: string, record: IdempotencyRecord): Promise<void>;
  listWatchlist(): Promise<WatchlistEntry[]>;
  createWatchlist(input: Omit<WatchlistEntry, "id">): Promise<WatchlistEntry>;
  updateWatchlist(id: string, input: Omit<WatchlistEntry, "id">): Promise<WatchlistEntry | null>;
  replaceWatchlist(entries: WatchlistEntry[]): Promise<WatchlistEntry[]>;
  deleteWatchlist(id: string): Promise<boolean>;
  listNotifications(): Promise<NotificationRecord[]>;
  listNotificationsPage(query: NotificationReadQuery): Promise<ReadPage<NotificationRecord>>;
  markNotificationRead(id: string, isRead: boolean): Promise<NotificationRecord | null>;
  listTopics(query: TopicReadQuery): Promise<ReadPage<Topic>>;
  getTopic(topicKey: string): Promise<Omit<TopicDetail, "serverTime"> | null>;
  listComments(): Promise<{ page: ReadPage<CommentProjection>; availability: CommentsAvailability }>;
}

export interface EncryptedConfigStore {
  set(key: string, encryptedValue: string): Promise<void>;
  get(key: string): Promise<string | null>;
  remove(key: string): Promise<void>;
}
