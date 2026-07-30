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
} from "../../src/domain.js";
import {
  decodeReadCursor,
  encodeReadCursor,
  type ReadPage,
  type ResearchRepository,
  type IdempotencyRecord,
  type PreferenceRecord,
  type PreferenceUpdate,
} from "../../src/repository.js";

const sourceItem = {
  id: "10000000-0000-4000-8000-000000000001",
  group: "US & Official" as const,
  externalID: "official-1",
  title: "Official model release",
  summary: "The original release notes.",
  author: "Official source",
  url: "https://example.com/release",
  publishedAt: "2026-07-23T08:00:00.000Z",
  collectedAt: "2026-07-23T08:05:00.000Z",
  language: "en",
  country: "US",
  topicKey: "model-release",
  isOriginalSource: true,
  credibility: 1,
  engagement: 10,
  verification: "Confirmed" as const,
};

export const fixtureOpportunity: Opportunity = {
  id: "20000000-0000-4000-8000-000000000001",
  topicKey: "model-release",
  title: "Official model release",
  brief: "The original release notes.",
  verification: "Confirmed",
  earliestPublishedAt: sourceItem.publishedAt,
  originalSource: sourceItem,
  items: [sourceItem],
  score: {
    freshness: 20,
    credibility: 20,
    momentum: 15,
    creatorActivity: 10,
    arabicCoverageGap: 15,
    regionalRelevance: 10,
  },
  regionalExplanation: "Relevant to Egypt and Gulf audiences.",
  coverageExplanation: "No Arabic-language coverage appears in the evidence.",
  disposition: "active",
  dispositionUpdatedAt: "2026-07-23T08:10:00.000Z",
  dispositionMutationID: null,
  isHighPriority: true,
};

export class MemoryRepository implements ResearchRepository {
  available = true;
  sourceHealth: SourceHealth[] = [{
    group: "YouTube",
    state: "Setup required",
    lastActivity: null,
    evidence: "No account or API credential has been connected.",
    repairAction: "Configure",
    dataTruth: "Missing",
  }];
  opportunities: Opportunity[] = [structuredClone(fixtureOpportunity)];
  watchlist: WatchlistEntry[] = [];
  notifications: NotificationRecord[] = [{
    id: "30000000-0000-4000-8000-000000000001",
    opportunityID: fixtureOpportunity.id,
    title: fixtureOpportunity.title,
    delivery: "Immediate",
    createdAt: "2026-07-23T08:10:00.000Z",
    isRead: false,
  }];
  preferences: PreferenceRecord = {
    refreshMinutes: 15,
    notificationsEnabled: false,
    digestHour: 18,
    quietHours: { enabled: false, start: "22:00", end: "08:00" },
    locale: "en",
    timeZone: "Africa/Cairo",
    updatedAt: "2026-07-23T08:10:00.000Z",
    etag: '"preferences-v1"',
  };
  private preferenceVersion = 1;
  private readonly idempotency = new Map<string, IdempotencyRecord>();
  private readonly idempotencyLocks = new Map<string, Promise<void>>();
  private readonly operatorSessions = new Map<string, Date>();

  async ping(): Promise<void> {
    if (!this.available) throw new Error("offline");
  }

  async createOperatorSession(tokenHash: string, expiresAt: Date): Promise<void> {
    this.operatorSessions.set(tokenHash, expiresAt);
  }

  async isOperatorSessionValid(tokenHash: string, observedAt: Date): Promise<boolean> {
    return (this.operatorSessions.get(tokenHash)?.getTime() ?? 0) > observedAt.getTime();
  }

  async deleteOperatorSession(tokenHash: string): Promise<void> {
    this.operatorSessions.delete(tokenHash);
  }

  async syncCursor(): Promise<string> {
    return `${this.opportunities.length}:${this.notifications.length}:${this.sourceHealth.map((item) => item.evidence).join("|")}`;
  }

  async upsertSourceHealth(health: SourceHealth): Promise<SourceHealth> {
    const index = this.sourceHealth.findIndex((candidate) => candidate.group === health.group);
    if (index === -1) this.sourceHealth.push(health);
    else this.sourceHealth[index] = health;
    return structuredClone(health);
  }

  async persistResearchBatch(batch: ResearchBatch): Promise<Opportunity> {
    const existing = this.opportunities.find((item) => item.topicKey === batch.topicKey);
    const items = batch.sourceItems.map((item, index) => ({
      id: `10000000-0000-4000-8000-${String(index + 2).padStart(12, "0")}`,
      ...item,
    }));
    const originalSource = batch.originalSource
      ? items.find((item) =>
        item.group === batch.originalSource?.group && item.externalID === batch.originalSource.externalID) ?? null
      : null;
    const opportunity: Opportunity = {
      id: existing?.id ?? `20000000-0000-4000-8000-${String(this.opportunities.length + 2).padStart(12, "0")}`,
      topicKey: batch.topicKey,
      verification: batch.verification,
      earliestPublishedAt: items.map((item) => item.publishedAt).sort()[0]!,
      originalSource,
      items,
      ...batch.opportunity,
      disposition: existing?.disposition ?? batch.opportunity.disposition,
      dispositionUpdatedAt: existing?.dispositionUpdatedAt ?? items[0]!.collectedAt,
      dispositionMutationID: existing?.dispositionMutationID ?? null,
      isHighPriority: Object.values(batch.opportunity.score).reduce((sum, value) => sum + value, 0) >= 75
        && batch.verification === "Confirmed",
    };
    if (existing) this.opportunities[this.opportunities.indexOf(existing)] = opportunity;
    else this.opportunities.push(opportunity);
    if (batch.notification) {
      this.notifications.push({
        id: `30000000-0000-4000-8000-${String(this.notifications.length + 2).padStart(12, "0")}`,
        opportunityID: opportunity.id,
        ...batch.notification,
      });
    }
    return structuredClone(opportunity);
  }

  async bootstrap(): Promise<BootstrapPayload> {
    return {
      sourceHealth: structuredClone(this.sourceHealth),
      opportunities: structuredClone(this.opportunities),
      watchlist: structuredClone(this.watchlist),
      notifications: structuredClone(this.notifications),
    };
  }

  async listSourceHealth(): Promise<SourceHealth[]> {
    return structuredClone(this.sourceHealth);
  }

  async listOpportunities(disposition?: OpportunityDisposition): Promise<Opportunity[]> {
    const opportunities = disposition
      ? this.opportunities.filter((opportunity) => opportunity.disposition === disposition)
      : this.opportunities;
    return structuredClone(opportunities);
  }

  async listOpportunitiesPage(query: OpportunityReadQuery): Promise<ReadPage<Opportunity>> {
    const sort = query.sort ?? "totalScore";
    let opportunities = this.opportunities.filter((opportunity) => {
      const latest = latestEvidenceDate(opportunity);
      return (!query.disposition || opportunity.disposition === query.disposition)
        && (!query.source || opportunity.items.some((item) => item.group === query.source))
        && (!query.topic || opportunity.topicKey === query.topic)
        && (!query.country || opportunity.items.some((item) => item.country.toLowerCase() === query.country!.toLowerCase()))
        && (!query.language || opportunity.items.some((item) => item.language.toLowerCase() === query.language!.toLowerCase()))
        && (!query.verification || opportunity.verification === query.verification)
        && (!query.freshness || query.freshness === "any" || freshnessIncludes(query.freshness, latest))
        && (!query.search || [opportunity.title, opportunity.brief, opportunity.topicKey, ...opportunity.items.flatMap((item) => [item.title, item.summary, item.author, item.topicKey])]
          .some((value) => value.toLowerCase().includes(query.search!.toLowerCase())));
    }).sort((left, right) => compareOpportunities(left, right, sort));
    if (query.cursor) {
      const cursor = decodeReadCursor(query.cursor, "opportunity", sort);
      const index = opportunities.findIndex((opportunity) => opportunity.id === cursor.id);
      opportunities = index === -1 ? [] : opportunities.slice(index + 1);
    }
    const limit = query.limit ?? 50;
    const items = opportunities.slice(0, limit);
    return {
      items: structuredClone(items),
      nextCursor: opportunities.length > limit
        ? encodeReadCursor({
          kind: "opportunity", sort, primary: 0, secondary: 0,
          timestamp: latestEvidenceDate(items[items.length - 1]!), id: items[items.length - 1]!.id,
        })
        : null,
    };
  }

  async getOpportunity(id: string): Promise<Opportunity | null> {
    return structuredClone(this.opportunities.find((opportunity) => opportunity.id === id) ?? null);
  }

  async updateOpportunityDisposition(
    id: string,
    mutation: OpportunityDispositionMutation,
  ): Promise<OpportunityDispositionState | null> {
    const opportunity = this.opportunities.find((candidate) => candidate.id === id);
    if (!opportunity) return null;
    const currentTime = new Date(opportunity.dispositionUpdatedAt).getTime();
    const incomingTime = new Date(mutation.changedAt).getTime();
    const normalizedMutationID = mutation.mutationID.toLowerCase();
    const isSameMutation = opportunity.dispositionMutationID?.toLowerCase() === normalizedMutationID;
    const wins = opportunity.dispositionMutationID === null
      || isSameMutation
      || incomingTime > currentTime
      || (incomingTime === currentTime && (opportunity.dispositionMutationID ?? "") < normalizedMutationID);
    if (wins && !isSameMutation) {
      opportunity.disposition = mutation.disposition;
      opportunity.dispositionUpdatedAt = mutation.changedAt;
      opportunity.dispositionMutationID = normalizedMutationID;
    }
    return {
      opportunityID: id,
      disposition: opportunity.disposition,
      changedAt: opportunity.dispositionUpdatedAt,
      mutationID: opportunity.dispositionMutationID ?? normalizedMutationID,
      outcome: isSameMutation ? "idempotent" : wins ? "applied" : "superseded",
    };
  }

  async getPreferences(): Promise<PreferenceRecord> {
    return structuredClone(this.preferences);
  }

  async updatePreferences(patch: PreferencesPatch, expectedETag: string): Promise<PreferenceUpdate> {
    if (expectedETag !== this.preferences.etag && expectedETag !== this.preferences.etag.replace(/^W\//, "")) {
      return { outcome: "conflict", current: structuredClone(this.preferences) };
    }
    const next: Preferences = {
      refreshMinutes: patch.refreshMinutes ?? this.preferences.refreshMinutes,
      notificationsEnabled: patch.notificationsEnabled ?? this.preferences.notificationsEnabled,
      digestHour: patch.digestHour ?? this.preferences.digestHour,
      quietHours: patch.quietHours ?? this.preferences.quietHours,
      locale: patch.locale ?? this.preferences.locale,
      timeZone: patch.timeZone ?? this.preferences.timeZone,
      updatedAt: new Date(Date.parse(this.preferences.updatedAt) + 1).toISOString(),
    };
    this.preferenceVersion += 1;
    this.preferences = { ...next, etag: `"preferences-v${this.preferenceVersion}"` };
    return { outcome: "updated", current: structuredClone(this.preferences) };
  }

  async withIdempotencyLock<T>(scope: string, key: string, operation: () => Promise<T>): Promise<T> {
    const lockKey = `${scope}:${key}`;
    const previous = this.idempotencyLocks.get(lockKey) ?? Promise.resolve();
    let release!: () => void;
    const current = new Promise<void>((resolve) => { release = resolve; });
    this.idempotencyLocks.set(lockKey, current);
    await previous;
    try {
      return await operation();
    } finally {
      release();
      if (this.idempotencyLocks.get(lockKey) === current) this.idempotencyLocks.delete(lockKey);
    }
  }

  async getIdempotencyRecord(scope: string, key: string): Promise<IdempotencyRecord | null> {
    return structuredClone(this.idempotency.get(`${scope}:${key}`) ?? null);
  }

  async saveIdempotencyRecord(scope: string, key: string, record: IdempotencyRecord): Promise<void> {
    if (scope.length > 300) throw new Error("idempotency scope exceeds persisted constraint");
    if (key.length > 255) throw new Error("idempotency key exceeds persisted constraint");
    this.idempotency.set(`${scope}:${key}`, structuredClone(record));
  }

  async listWatchlist(): Promise<WatchlistEntry[]> {
    return structuredClone(this.watchlist);
  }

  async createWatchlist(input: Omit<WatchlistEntry, "id">): Promise<WatchlistEntry> {
    const entry = { id: "40000000-0000-4000-8000-000000000001", ...input };
    this.watchlist.push(entry);
    return structuredClone(entry);
  }

  async updateWatchlist(
    id: string,
    input: Omit<WatchlistEntry, "id">,
  ): Promise<WatchlistEntry | null> {
    const index = this.watchlist.findIndex((entry) => entry.id === id);
    if (index === -1) return null;
    this.watchlist[index] = { id, ...input };
    return structuredClone(this.watchlist[index]);
  }

  async replaceWatchlist(entries: WatchlistEntry[]): Promise<WatchlistEntry[]> {
    this.watchlist = structuredClone(entries);
    return structuredClone(this.watchlist);
  }

  async deleteWatchlist(id: string): Promise<boolean> {
    const index = this.watchlist.findIndex((entry) => entry.id === id);
    if (index === -1) return false;
    this.watchlist.splice(index, 1);
    return true;
  }

  async listNotifications(): Promise<NotificationRecord[]> {
    return structuredClone(this.notifications);
  }

  async listNotificationsPage(query: NotificationReadQuery): Promise<ReadPage<NotificationRecord>> {
    let notifications = this.notifications.filter((notification) => (
      (query.isRead === undefined || notification.isRead === query.isRead)
      && (!query.delivery || notification.delivery === query.delivery)
      && (!query.search || notification.title.toLowerCase().includes(query.search.toLowerCase()))
    )).sort((left, right) => {
      const date = right.createdAt.localeCompare(left.createdAt);
      return date || left.id.localeCompare(right.id);
    });
    if (query.cursor) {
      const cursor = decodeReadCursor(query.cursor, "notification", "createdAt");
      const index = notifications.findIndex((notification) => notification.id === cursor.id);
      notifications = index === -1 ? [] : notifications.slice(index + 1);
    }
    const limit = query.limit ?? 50;
    const items = notifications.slice(0, limit);
    return {
      items: structuredClone(items),
      nextCursor: notifications.length > limit
        ? encodeReadCursor({
          kind: "notification", sort: "createdAt", primary: 0, secondary: 0,
          timestamp: items[items.length - 1]!.createdAt, id: items[items.length - 1]!.id,
        })
        : null,
    };
  }

  async listTopics(query: TopicReadQuery): Promise<ReadPage<Topic>> {
    const grouped = new Map<string, Opportunity[]>();
    for (const opportunity of this.opportunities) {
      grouped.set(opportunity.topicKey, [...(grouped.get(opportunity.topicKey) ?? []), opportunity]);
    }
    let topics = [...grouped.entries()]
      .map(([topicKey, opportunities]) => topicFromOpportunities(topicKey, opportunities))
      .filter((topic) => !query.search || topic.topicKey.toLowerCase().includes(query.search.toLowerCase()) || topic.title.toLowerCase().includes(query.search.toLowerCase()))
      .sort((left, right) => right.latestActivityAt.localeCompare(left.latestActivityAt) || left.topicKey.localeCompare(right.topicKey));
    if (query.cursor) {
      const cursor = decodeReadCursor(query.cursor, "topic", "latestActivityAt");
      const index = topics.findIndex((topic) => topic.topicKey === cursor.id);
      topics = index === -1 ? [] : topics.slice(index + 1);
    }
    const limit = query.limit ?? 50;
    const items = topics.slice(0, limit);
    return {
      items,
      nextCursor: topics.length > limit
        ? encodeReadCursor({
          kind: "topic", sort: "latestActivityAt", primary: 0, secondary: 0,
          timestamp: items[items.length - 1]!.latestActivityAt, id: items[items.length - 1]!.topicKey,
        })
        : null,
    };
  }

  async getTopic(topicKey: string): Promise<Omit<TopicDetail, "serverTime"> | null> {
    const opportunities = this.opportunities.filter((opportunity) => opportunity.topicKey === topicKey);
    if (opportunities.length === 0) return null;
    return { ...topicFromOpportunities(topicKey, opportunities), opportunities: structuredClone(opportunities.slice(0, 100)) };
  }

  async listComments(): Promise<{ page: ReadPage<CommentProjection>; availability: CommentsAvailability }> {
    const health = this.sourceHealth.find((candidate) => candidate.group === "Comments");
    return {
      page: { items: [], nextCursor: null },
      availability: health
        ? { group: "Comments", state: health.state, dataTruth: health.dataTruth, evidence: health.evidence, repairAction: health.repairAction }
        : {
          group: "Comments", state: "Unavailable", dataTruth: "Unavailable",
          evidence: "Comments source health is unavailable.", repairAction: "Check the backend source-health record.",
        },
    };
  }

  async markNotificationRead(id: string, isRead: boolean): Promise<NotificationRecord | null> {
    const notification = this.notifications.find((candidate) => candidate.id === id);
    if (!notification) return null;
    notification.isRead = isRead;
    return structuredClone(notification);
  }
}

function latestEvidenceDate(opportunity: Opportunity): string {
  return opportunity.items.map((item) => item.publishedAt).sort().at(-1) ?? opportunity.earliestPublishedAt;
}

function freshnessIncludes(freshness: NonNullable<OpportunityReadQuery["freshness"]>, latest: string): boolean {
  if (freshness === "any") return true;
  const intervals = { lastHour: 3_600_000, lastDay: 86_400_000, lastThreeDays: 3 * 86_400_000, lastWeek: 7 * 86_400_000 };
  return Date.parse(latest) >= Date.now() - intervals[freshness];
}

function compareOpportunities(left: Opportunity, right: Opportunity, sort: NonNullable<OpportunityReadQuery["sort"]> | "totalScore"): number {
  const leftLatest = latestEvidenceDate(left);
  const rightLatest = latestEvidenceDate(right);
  const score = right.score.freshness + right.score.credibility + right.score.momentum + right.score.creatorActivity
    + right.score.arabicCoverageGap + right.score.regionalRelevance
    - (left.score.freshness + left.score.credibility + left.score.momentum + left.score.creatorActivity
      + left.score.arabicCoverageGap + left.score.regionalRelevance);
  if (sort === "newest" && leftLatest !== rightLatest) return rightLatest.localeCompare(leftLatest);
  if (sort === "highPriority" && left.isHighPriority !== right.isHighPriority) return left.isHighPriority ? -1 : 1;
  if (sort === "regionalRelevance" && left.score.regionalRelevance !== right.score.regionalRelevance) {
    return right.score.regionalRelevance - left.score.regionalRelevance;
  }
  if (sort === "arabicCoverageGap" && left.score.arabicCoverageGap !== right.score.arabicCoverageGap) {
    return right.score.arabicCoverageGap - left.score.arabicCoverageGap;
  }
  if (score !== 0) return score;
  if (leftLatest !== rightLatest) return rightLatest.localeCompare(leftLatest);
  return left.id.localeCompare(right.id);
}

function topicFromOpportunities(topicKey: string, opportunities: Opportunity[]): Topic {
  const latestPublishedAt = opportunities.map(latestEvidenceDate).sort().at(-1)!;
  const latestActivityAt = opportunities.map((opportunity) => opportunity.dispositionUpdatedAt).sort().at(-1) ?? latestPublishedAt;
  const title = [...opportunities].sort((left, right) => right.dispositionUpdatedAt.localeCompare(left.dispositionUpdatedAt) || left.title.localeCompare(right.title))[0]!.title;
  const age = Date.now() - Date.parse(latestPublishedAt);
  return {
    topicKey,
    title,
    opportunityCount: opportunities.length,
    freshness: age <= 3_600_000 ? "lastHour" : age <= 86_400_000 ? "lastDay" : age <= 3 * 86_400_000 ? "lastThreeDays" : age <= 7 * 86_400_000 ? "lastWeek" : "older",
    verificationMix: {
      confirmed: opportunities.filter((item) => item.verification === "Confirmed").length,
      disputed: opportunities.filter((item) => item.verification === "Disputed").length,
      unverified: opportunities.filter((item) => item.verification === "Unverified").length,
    },
    latestPublishedAt,
    latestActivityAt,
  };
}
