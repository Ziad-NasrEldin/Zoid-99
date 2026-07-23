import pg from "pg";
import type {
  BootstrapPayload,
  NotificationRecord,
  Opportunity,
  OpportunityDisposition,
  ResearchBatch,
  SourceHealth,
  SourceItem,
  WatchlistEntry,
} from "./domain.js";
import type { EncryptedConfigStore, ResearchRepository } from "./repository.js";

const { Pool } = pg;
type OpportunityRow = {
  id: string;
  story_cluster_id: string;
  topic_key: string;
  title: string;
  brief: string;
  verification: Opportunity["verification"];
  earliest_published_at: Date;
  original_source_item_id: string | null;
  freshness_score: number;
  credibility_score: number;
  momentum_score: number;
  creator_activity_score: number;
  arabic_coverage_gap_score: number;
  regional_relevance_score: number;
  regional_explanation: string;
  coverage_explanation: string;
  disposition: OpportunityDisposition;
};

type SourceItemRow = {
  id: string;
  source_group: SourceItem["group"];
  external_id: string;
  title: string;
  summary: string;
  author: string;
  source_url: string;
  published_at: Date;
  collected_at: Date;
  language: string;
  country: string;
  topic_key: string;
  is_original_source: boolean;
  credibility: string;
  engagement: string;
  verification: SourceItem["verification"];
  opportunity_id: string;
};

export function createPool(databaseUrl: string): pg.Pool {
  return new Pool({
    connectionString: databaseUrl,
    max: 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
    application_name: "zoid99-backend",
  });
}

export class PostgreSqlRepository implements ResearchRepository, EncryptedConfigStore {
  constructor(private readonly database: pg.Pool) {}

  async ping(): Promise<void> {
    await this.database.query("SELECT 1");
  }

  async upsertSourceHealth(health: SourceHealth): Promise<SourceHealth> {
    const result = await this.database.query<{
      source_group: SourceHealth["group"];
      connection_state: SourceHealth["state"];
      last_activity_at: Date | null;
      evidence: string;
      repair_action: string;
    }>(`
      INSERT INTO source_health (
        source_group, sort_order, connection_state, last_activity_at, evidence, repair_action
      ) VALUES (
        $1, (SELECT sort_order FROM source_health WHERE source_group = $1),
        $2, $3, $4, $5
      )
      ON CONFLICT (source_group) DO UPDATE SET
        connection_state = EXCLUDED.connection_state,
        last_activity_at = EXCLUDED.last_activity_at,
        evidence = EXCLUDED.evidence,
        repair_action = EXCLUDED.repair_action,
        updated_at = now()
      RETURNING source_group, connection_state, last_activity_at, evidence, repair_action
    `, [health.group, health.state, health.lastActivity, health.evidence, health.repairAction]);
    const row = result.rows[0]!;
    return {
      group: row.source_group,
      state: row.connection_state,
      lastActivity: row.last_activity_at?.toISOString() ?? null,
      evidence: row.evidence,
      repairAction: row.repair_action,
    };
  }

  async persistResearchBatch(batch: ResearchBatch): Promise<Opportunity> {
    if (batch.sourceItems.length === 0) throw new Error("A research batch requires at least one source item");
    const client = await this.database.connect();
    try {
      await client.query("BEGIN");
      const itemIDs = new Map<string, string>();
      for (const item of batch.sourceItems) {
        const result = await client.query<{ id: string }>(`
          INSERT INTO source_items (
            source_group, external_id, title, summary, author, source_url,
            published_at, collected_at, language, country, topic_key,
            is_original_source, credibility, engagement, verification
          ) VALUES (
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15
          )
          ON CONFLICT (source_group, external_id) DO UPDATE SET
            title = EXCLUDED.title,
            summary = EXCLUDED.summary,
            author = EXCLUDED.author,
            source_url = EXCLUDED.source_url,
            published_at = EXCLUDED.published_at,
            collected_at = EXCLUDED.collected_at,
            language = EXCLUDED.language,
            country = EXCLUDED.country,
            topic_key = EXCLUDED.topic_key,
            is_original_source = EXCLUDED.is_original_source,
            credibility = EXCLUDED.credibility,
            engagement = EXCLUDED.engagement,
            verification = EXCLUDED.verification
          RETURNING id
        `, [
          item.group, item.externalID, item.title, item.summary, item.author, item.url,
          item.publishedAt, item.collectedAt, item.language, item.country, item.topicKey,
          item.isOriginalSource, item.credibility, item.engagement, item.verification,
        ]);
        itemIDs.set(`${item.group}:${item.externalID}`, result.rows[0]!.id);
      }
      const originalSourceID = batch.originalSource === null
        ? null
        : itemIDs.get(`${batch.originalSource.group}:${batch.originalSource.externalID}`) ?? null;
      const originalSourceItem = batch.originalSource === null
        ? null
        : batch.sourceItems.find((item) =>
          item.group === batch.originalSource!.group && item.externalID === batch.originalSource!.externalID);
      if (batch.originState === "Identified" && originalSourceID === null) {
        throw new Error("The identified original source must be included in the research batch");
      }
      if (batch.originState === "Identified" && !originalSourceItem?.isOriginalSource) {
        throw new Error("The identified original source must be marked as original evidence");
      }
      if (batch.originState === "Unknown" && batch.originalSource !== null) {
        throw new Error("An unknown origin cannot name an original source");
      }
      const earliestPublishedAt = batch.sourceItems
        .map((item) => new Date(item.publishedAt))
        .sort((left, right) => left.getTime() - right.getTime())[0]!.toISOString();
      const clusterResult = await client.query<{ id: string }>(`
        INSERT INTO story_clusters (
          cluster_key, topic_key, verification, origin_state,
          original_source_item_id, earliest_published_at
        ) VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (cluster_key) DO UPDATE SET
          topic_key = EXCLUDED.topic_key,
          verification = EXCLUDED.verification,
          origin_state = EXCLUDED.origin_state,
          original_source_item_id = EXCLUDED.original_source_item_id,
          earliest_published_at = LEAST(story_clusters.earliest_published_at, EXCLUDED.earliest_published_at),
          updated_at = now()
        RETURNING id
      `, [
        batch.clusterKey, batch.topicKey, batch.verification, batch.originState,
        originalSourceID, earliestPublishedAt,
      ]);
      const clusterID = clusterResult.rows[0]!.id;
      for (const itemID of itemIDs.values()) {
        await client.query(`
          INSERT INTO story_cluster_items (story_cluster_id, source_item_id)
          VALUES ($1, $2)
          ON CONFLICT (story_cluster_id, source_item_id) DO NOTHING
        `, [clusterID, itemID]);
      }
      const opportunityResult = await client.query<{ id: string }>(`
        INSERT INTO opportunities (
          story_cluster_id, title, brief, freshness_score, credibility_score,
          momentum_score, creator_activity_score, arabic_coverage_gap_score,
          regional_relevance_score, regional_explanation, coverage_explanation, disposition
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        ON CONFLICT (story_cluster_id) DO UPDATE SET
          title = EXCLUDED.title,
          brief = EXCLUDED.brief,
          freshness_score = EXCLUDED.freshness_score,
          credibility_score = EXCLUDED.credibility_score,
          momentum_score = EXCLUDED.momentum_score,
          creator_activity_score = EXCLUDED.creator_activity_score,
          arabic_coverage_gap_score = EXCLUDED.arabic_coverage_gap_score,
          regional_relevance_score = EXCLUDED.regional_relevance_score,
          regional_explanation = EXCLUDED.regional_explanation,
          coverage_explanation = EXCLUDED.coverage_explanation,
          updated_at = now()
        RETURNING id
      `, [
        clusterID, batch.opportunity.title, batch.opportunity.brief,
        batch.opportunity.score.freshness, batch.opportunity.score.credibility,
        batch.opportunity.score.momentum, batch.opportunity.score.creatorActivity,
        batch.opportunity.score.arabicCoverageGap, batch.opportunity.score.regionalRelevance,
        batch.opportunity.regionalExplanation, batch.opportunity.coverageExplanation,
        batch.opportunity.disposition,
      ]);
      const opportunityID = opportunityResult.rows[0]!.id;
      if (batch.notification) {
        await client.query(`
          INSERT INTO notifications (
            opportunity_id, title, delivery, created_at, is_read
          ) VALUES ($1, $2, $3, $4, $5)
          ON CONFLICT (opportunity_id, delivery) DO UPDATE SET
            title = EXCLUDED.title,
            created_at = EXCLUDED.created_at
        `, [
          opportunityID, batch.notification.title, batch.notification.delivery,
          batch.notification.createdAt, batch.notification.isRead,
        ]);
      }
      await client.query("COMMIT");
      return (await this.getOpportunity(opportunityID))!;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async bootstrap(): Promise<BootstrapPayload> {
    const [sourceHealth, opportunities, watchlist, notifications] = await Promise.all([
      this.listSourceHealth(),
      this.listOpportunities(),
      this.listWatchlist(),
      this.listNotifications(),
    ]);
    return { sourceHealth, opportunities, watchlist, notifications };
  }

  async listSourceHealth(): Promise<SourceHealth[]> {
    const result = await this.database.query<{
      source_group: SourceHealth["group"];
      connection_state: SourceHealth["state"];
      last_activity_at: Date | null;
      evidence: string;
      repair_action: string;
    }>(`
      SELECT source_group, connection_state, last_activity_at, evidence, repair_action
      FROM source_health
      ORDER BY sort_order
    `);
    return result.rows.map((row) => ({
      group: row.source_group,
      state: row.connection_state,
      lastActivity: row.last_activity_at?.toISOString() ?? null,
      evidence: row.evidence,
      repairAction: row.repair_action,
    }));
  }

  async listOpportunities(disposition?: OpportunityDisposition): Promise<Opportunity[]> {
    const values: unknown[] = [];
    const filter = disposition ? "WHERE o.disposition = $1" : "";
    if (disposition) values.push(disposition);
    const result = await this.database.query<OpportunityRow>(`
      SELECT o.*, sc.topic_key, sc.verification, sc.earliest_published_at, sc.original_source_item_id
      FROM opportunities o
      JOIN story_clusters sc ON sc.id = o.story_cluster_id
      ${filter}
      ORDER BY (
        o.freshness_score + o.credibility_score + o.momentum_score +
        o.creator_activity_score + o.arabic_coverage_gap_score + o.regional_relevance_score
      ) DESC, sc.earliest_published_at DESC
    `, values);
    return this.hydrateOpportunities(result.rows);
  }

  async getOpportunity(id: string): Promise<Opportunity | null> {
    const result = await this.database.query<OpportunityRow>(`
      SELECT o.*, sc.topic_key, sc.verification, sc.earliest_published_at, sc.original_source_item_id
      FROM opportunities o
      JOIN story_clusters sc ON sc.id = o.story_cluster_id
      WHERE o.id = $1
    `, [id]);
    return (await this.hydrateOpportunities(result.rows))[0] ?? null;
  }

  async updateOpportunityDisposition(id: string, disposition: OpportunityDisposition): Promise<Opportunity | null> {
    await this.database.query(`
      UPDATE opportunities SET disposition = $2, updated_at = now()
      WHERE id = $1
    `, [id, disposition]);
    return this.getOpportunity(id);
  }

  async listWatchlist(): Promise<WatchlistEntry[]> {
    const result = await this.database.query<{
      id: string;
      kind: WatchlistEntry["kind"];
      value: string;
      high_priority: boolean;
    }>("SELECT id, kind, value, high_priority FROM watchlist_entries ORDER BY created_at, id");
    return result.rows.map((row) => ({
      id: row.id,
      kind: row.kind,
      value: row.value,
      highPriority: row.high_priority,
    }));
  }

  async createWatchlist(input: Omit<WatchlistEntry, "id">): Promise<WatchlistEntry> {
    const result = await this.database.query<{ id: string }>(`
      INSERT INTO watchlist_entries (kind, value, high_priority)
      VALUES ($1, $2, $3)
      RETURNING id
    `, [input.kind, input.value, input.highPriority]);
    return { id: result.rows[0]!.id, ...input };
  }

  async deleteWatchlist(id: string): Promise<boolean> {
    const result = await this.database.query("DELETE FROM watchlist_entries WHERE id = $1", [id]);
    return result.rowCount === 1;
  }

  async listNotifications(): Promise<NotificationRecord[]> {
    const result = await this.database.query<{
      id: string;
      opportunity_id: string;
      title: string;
      delivery: NotificationRecord["delivery"];
      created_at: Date;
      is_read: boolean;
    }>(`
      SELECT id, opportunity_id, title, delivery, created_at, is_read
      FROM notifications
      ORDER BY created_at DESC, id
    `);
    return result.rows.map((row) => ({
      id: row.id,
      opportunityID: row.opportunity_id,
      title: row.title,
      delivery: row.delivery,
      createdAt: row.created_at.toISOString(),
      isRead: row.is_read,
    }));
  }

  async markNotificationRead(id: string, isRead: boolean): Promise<NotificationRecord | null> {
    const result = await this.database.query<{
      id: string;
      opportunity_id: string;
      title: string;
      delivery: NotificationRecord["delivery"];
      created_at: Date;
      is_read: boolean;
    }>(`
      UPDATE notifications SET is_read = $2
      WHERE id = $1
      RETURNING id, opportunity_id, title, delivery, created_at, is_read
    `, [id, isRead]);
    const row = result.rows[0];
    return row ? {
      id: row.id,
      opportunityID: row.opportunity_id,
      title: row.title,
      delivery: row.delivery,
      createdAt: row.created_at.toISOString(),
      isRead: row.is_read,
    } : null;
  }

  async set(key: string, encryptedValue: string): Promise<void> {
    await this.database.query(`
      INSERT INTO encrypted_configs (config_key, encrypted_value)
      VALUES ($1, $2)
      ON CONFLICT (config_key) DO UPDATE
      SET encrypted_value = EXCLUDED.encrypted_value, updated_at = now()
    `, [key, encryptedValue]);
  }

  async get(key: string): Promise<string | null> {
    const result = await this.database.query<{ encrypted_value: string }>(
      "SELECT encrypted_value FROM encrypted_configs WHERE config_key = $1",
      [key],
    );
    return result.rows[0]?.encrypted_value ?? null;
  }

  private async hydrateOpportunities(rows: OpportunityRow[]): Promise<Opportunity[]> {
    if (rows.length === 0) return [];
    const clusterIDs = rows.map((row) => row.story_cluster_id);
    const itemResult = await this.database.query<SourceItemRow>(`
      SELECT si.*, sci.story_cluster_id AS opportunity_id
      FROM story_cluster_items sci
      JOIN source_items si ON si.id = sci.source_item_id
      WHERE sci.story_cluster_id = ANY($1::uuid[])
      ORDER BY si.published_at, si.id
    `, [clusterIDs]);
    const itemsByOpportunity = new Map<string, SourceItemRow[]>();
    for (const row of itemResult.rows) {
      const existing = itemsByOpportunity.get(row.opportunity_id) ?? [];
      existing.push(row);
      itemsByOpportunity.set(row.opportunity_id, existing);
    }
    return rows.map((row) => {
      const items = (itemsByOpportunity.get(row.story_cluster_id) ?? []).map(mapSourceItem);
      const score = {
        freshness: row.freshness_score,
        credibility: row.credibility_score,
        momentum: row.momentum_score,
        creatorActivity: row.creator_activity_score,
        arabicCoverageGap: row.arabic_coverage_gap_score,
        regionalRelevance: row.regional_relevance_score,
      };
      const total = Object.values(score).reduce((sum, value) => sum + value, 0);
      return {
        id: row.id,
        topicKey: row.topic_key,
        title: row.title,
        brief: row.brief,
        verification: row.verification,
        earliestPublishedAt: row.earliest_published_at.toISOString(),
        originalSource: items.find((item) => item.id === row.original_source_item_id) ?? null,
        items,
        score,
        regionalExplanation: row.regional_explanation,
        coverageExplanation: row.coverage_explanation,
        disposition: row.disposition,
        isHighPriority: total >= 75 && row.verification === "Confirmed",
      };
    });
  }
}

function mapSourceItem(row: SourceItemRow): SourceItem {
  return {
    id: row.id,
    group: row.source_group,
    externalID: row.external_id,
    title: row.title,
    summary: row.summary,
    author: row.author,
    url: row.source_url,
    publishedAt: row.published_at.toISOString(),
    collectedAt: row.collected_at.toISOString(),
    language: row.language,
    country: row.country,
    topicKey: row.topic_key,
    isOriginalSource: row.is_original_source,
    credibility: Number(row.credibility),
    engagement: Number(row.engagement),
    verification: row.verification,
  };
}
