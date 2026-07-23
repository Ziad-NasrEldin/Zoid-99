import type {
  BootstrapPayload,
  NotificationRecord,
  Opportunity,
  OpportunityDisposition,
  OpportunityDispositionMutation,
  OpportunityDispositionState,
  ResearchBatch,
  SourceHealth,
  WatchlistEntry,
} from "../../src/domain.js";
import type { ResearchRepository } from "../../src/repository.js";

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

  async ping(): Promise<void> {
    if (!this.available) throw new Error("offline");
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

  async listWatchlist(): Promise<WatchlistEntry[]> {
    return structuredClone(this.watchlist);
  }

  async createWatchlist(input: Omit<WatchlistEntry, "id">): Promise<WatchlistEntry> {
    const entry = { id: "40000000-0000-4000-8000-000000000001", ...input };
    this.watchlist.push(entry);
    return structuredClone(entry);
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

  async markNotificationRead(id: string, isRead: boolean): Promise<NotificationRecord | null> {
    const notification = this.notifications.find((candidate) => candidate.id === id);
    if (!notification) return null;
    notification.isRead = isRead;
    return structuredClone(notification);
  }
}
