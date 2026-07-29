import pg from "pg";
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
  SourceItem,
  WatchlistEntry,
  Topic,
  TopicDetail,
  TopicReadQuery,
} from "./domain.js";
import {
  decodeReadCursor,
  encodeReadCursor,
  type EncryptedConfigStore,
  type IdempotencyRecord,
  type PreferenceRecord,
  type PreferenceUpdate,
  type ReadPage,
  type ReadCursor,
  type ResearchRepository,
} from "./repository.js";

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
  disposition_updated_at: Date;
  disposition_mutation_id: string | null;
  latest_published_at?: Date;
  latest_published_at_text?: string;
  rank_score?: number;
  high_priority?: boolean;
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

  async createOperatorSession(tokenHash: string, expiresAt: Date): Promise<void> {
    await this.database.query("DELETE FROM operator_sessions WHERE expires_at <= now()");
    await this.database.query(
      `INSERT INTO operator_sessions (token_hash, expires_at)
       VALUES ($1, $2)`,
      [tokenHash, expiresAt],
    );
  }

  async isOperatorSessionValid(tokenHash: string, observedAt: Date): Promise<boolean> {
    const result = await this.database.query(
      `SELECT 1
       FROM operator_sessions
       WHERE token_hash = $1 AND expires_at > $2`,
      [tokenHash, observedAt],
    );
    return result.rowCount === 1;
  }

  async deleteOperatorSession(tokenHash: string): Promise<void> {
    await this.database.query("DELETE FROM operator_sessions WHERE token_hash = $1", [tokenHash]);
  }

  async syncCursor(): Promise<string> {
    const result = await this.database.query<{ cursor: Date }>(`
      SELECT GREATEST(
        COALESCE((SELECT max(updated_at) FROM source_health), to_timestamp(0)),
        COALESCE((SELECT max(updated_at) FROM opportunities), to_timestamp(0)),
        COALESCE((SELECT max(updated_at) FROM watchlist_entries), to_timestamp(0)),
        COALESCE((SELECT max(updated_at) FROM notifications), to_timestamp(0)),
        COALESCE((SELECT max(updated_at) FROM single_user_settings), to_timestamp(0))
      ) AS cursor
    `);
    return result.rows[0]!.cursor.toISOString();
  }

  async getPreferences(): Promise<PreferenceRecord> {
    const result = await this.database.query<{
      refresh_minutes: number;
      notifications_enabled: boolean;
      digest_hour: number;
      quiet_hours_enabled: boolean;
      quiet_hours_start: string;
      quiet_hours_end: string;
      locale: string;
      time_zone: string;
      updated_at: Date;
      version: string;
    }>(`
      SELECT refresh_minutes, notifications_enabled, digest_hour,
        quiet_hours_enabled, quiet_hours_start, quiet_hours_end,
        locale, time_zone, updated_at, version
      FROM single_user_settings
      WHERE singleton = true
    `);
    const row = result.rows[0];
    if (!row) throw new Error("The single-user preferences row is missing");
    return mapPreferences(row);
  }

  async updatePreferences(patch: PreferencesPatch, expectedETag: string): Promise<PreferenceUpdate> {
    const client = await this.database.connect();
    try {
      await client.query("BEGIN");
      const currentResult = await client.query<{
        refresh_minutes: number;
        notifications_enabled: boolean;
        digest_hour: number;
        quiet_hours_enabled: boolean;
        quiet_hours_start: string;
        quiet_hours_end: string;
        locale: string;
        time_zone: string;
        updated_at: Date;
        version: string;
      }>(`
        SELECT refresh_minutes, notifications_enabled, digest_hour,
          quiet_hours_enabled, quiet_hours_start, quiet_hours_end,
          locale, time_zone, updated_at, version
        FROM single_user_settings
        WHERE singleton = true
        FOR UPDATE
      `);
      const currentRow = currentResult.rows[0];
      if (!currentRow) throw new Error("The single-user preferences row is missing");
      const current = mapPreferences(currentRow);
      if (normalizeETag(expectedETag) !== normalizeETag(current.etag)) {
        await client.query("COMMIT");
        return { outcome: "conflict", current };
      }

      const assignments: string[] = [];
      const values: unknown[] = [];
      const add = (column: string, value: unknown): void => {
        assignments.push(`${column} = $${values.length + 1}`);
        values.push(value);
      };
      if (patch.refreshMinutes !== undefined) add("refresh_minutes", patch.refreshMinutes);
      if (patch.notificationsEnabled !== undefined) add("notifications_enabled", patch.notificationsEnabled);
      if (patch.digestHour !== undefined) add("digest_hour", patch.digestHour);
      if (patch.quietHours !== undefined) {
        add("quiet_hours_enabled", patch.quietHours.enabled);
        add("quiet_hours_start", patch.quietHours.start);
        add("quiet_hours_end", patch.quietHours.end);
      }
      if (patch.locale !== undefined) add("locale", patch.locale);
      if (patch.timeZone !== undefined) add("time_zone", patch.timeZone);
      values.push(true);
      const updated = await client.query<{
        refresh_minutes: number;
        notifications_enabled: boolean;
        digest_hour: number;
        quiet_hours_enabled: boolean;
        quiet_hours_start: string;
        quiet_hours_end: string;
        locale: string;
        time_zone: string;
        updated_at: Date;
        version: string;
      }>(`
        UPDATE single_user_settings
        SET ${assignments.join(", ")}, updated_at = clock_timestamp(), version = version + 1
        WHERE singleton = $${values.length}
        RETURNING refresh_minutes, notifications_enabled, digest_hour,
          quiet_hours_enabled, quiet_hours_start, quiet_hours_end,
          locale, time_zone, updated_at, version
      `, values);
      await client.query("COMMIT");
      return { outcome: "updated", current: mapPreferences(updated.rows[0]!) };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async withIdempotencyLock<T>(scope: string, key: string, operation: () => Promise<T>): Promise<T> {
    const client = await this.database.connect();
    const lockKey = `${scope}:${key}`;
    try {
      await client.query("SELECT pg_advisory_lock(hashtext($1))", [lockKey]);
      return await operation();
    } finally {
      await client.query("SELECT pg_advisory_unlock(hashtext($1))", [lockKey]).catch(() => undefined);
      client.release();
    }
  }

  async getIdempotencyRecord(scope: string, key: string): Promise<IdempotencyRecord | null> {
    const result = await this.database.query<{
      request_hash: string;
      status_code: number;
      response_body: unknown;
      response_headers: Record<string, string>;
    }>(`
      SELECT request_hash, status_code, response_body, response_headers
      FROM mutation_idempotency
      WHERE scope = $1 AND idempotency_key = $2 AND expires_at > now()
    `, [scope, key]);
    const row = result.rows[0];
    return row ? {
      requestHash: row.request_hash,
      statusCode: row.status_code,
      responseBody: row.response_body,
      responseHeaders: row.response_headers,
    } : null;
  }

  async saveIdempotencyRecord(scope: string, key: string, record: IdempotencyRecord): Promise<void> {
    // PostgreSQL treats a JavaScript null parameter as SQL NULL. Persist JSON null
    // instead so successful empty responses, such as DELETE 204, remain replayable.
    const responseBody = record.responseBody === null ? "null" : record.responseBody;
    await this.database.query(`
      INSERT INTO mutation_idempotency (scope, idempotency_key, request_hash, status_code, response_body, response_headers)
      VALUES ($1, $2, $3, $4, $5, $6)
      ON CONFLICT (scope, idempotency_key) DO UPDATE SET
        request_hash = EXCLUDED.request_hash,
        status_code = EXCLUDED.status_code,
        response_body = EXCLUDED.response_body,
        response_headers = EXCLUDED.response_headers,
        created_at = now(),
        expires_at = now() + interval '24 hours'
      WHERE mutation_idempotency.expires_at <= now()
    `, [scope, key, record.requestHash, record.statusCode, responseBody, record.responseHeaders ?? {}]);
  }

  async upsertSourceHealth(health: SourceHealth): Promise<SourceHealth> {
    const result = await this.database.query<{
      source_group: SourceHealth["group"];
      connection_state: SourceHealth["state"];
      last_activity_at: Date | null;
      evidence: string;
      repair_action: string;
      data_truth: SourceHealth["dataTruth"];
    }>(`
      INSERT INTO source_health (
        source_group, sort_order, connection_state, last_activity_at, evidence, repair_action, data_truth
      ) VALUES (
        $1, (SELECT sort_order FROM source_health WHERE source_group = $1),
        $2, $3, $4, $5, $6
      )
      ON CONFLICT (source_group) DO UPDATE SET
        connection_state = EXCLUDED.connection_state,
        last_activity_at = EXCLUDED.last_activity_at,
        evidence = EXCLUDED.evidence,
        repair_action = EXCLUDED.repair_action,
        data_truth = EXCLUDED.data_truth,
        updated_at = now()
      RETURNING source_group, connection_state, last_activity_at, evidence, repair_action, data_truth
    `, [health.group, health.state, health.lastActivity, health.evidence, health.repairAction, health.dataTruth]);
    const row = result.rows[0]!;
    return {
      group: row.source_group,
      state: row.connection_state,
      lastActivity: row.last_activity_at?.toISOString() ?? null,
      evidence: row.evidence,
      repairAction: row.repair_action,
      dataTruth: row.data_truth,
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
      data_truth: SourceHealth["dataTruth"];
    }>(`
      SELECT source_group, connection_state, last_activity_at, evidence, repair_action, data_truth
      FROM source_health
      ORDER BY sort_order
    `);
    return result.rows.map((row) => ({
      group: row.source_group,
      state: row.connection_state,
      lastActivity: row.last_activity_at?.toISOString() ?? null,
      evidence: row.evidence,
      repairAction: row.repair_action,
      dataTruth: row.data_truth,
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
      ) DESC, sc.earliest_published_at DESC, sc.cluster_key
    `, values);
    return this.hydrateOpportunities(result.rows);
  }

  async listOpportunitiesPage(query: OpportunityReadQuery): Promise<ReadPage<Opportunity>> {
    const sort = query.sort ?? "totalScore";
    const values: unknown[] = [];
    const conditions: string[] = [];
    const add = (value: unknown): string => {
      values.push(value);
      return `$${values.length}`;
    };
    if (query.disposition) conditions.push(`ranked.disposition = ${add(query.disposition)}`);
    if (query.source) conditions.push(`EXISTS (
      SELECT 1 FROM story_cluster_items source_filter_sci
      JOIN source_items source_filter_si ON source_filter_si.id = source_filter_sci.source_item_id
      WHERE source_filter_sci.story_cluster_id = ranked.story_cluster_id
        AND source_filter_si.source_group = ${add(query.source)}
    )`);
    if (query.topic) conditions.push(`ranked.topic_key = ${add(query.topic)}`);
    if (query.country) conditions.push(`EXISTS (
      SELECT 1 FROM story_cluster_items country_filter_sci
      JOIN source_items country_filter_si ON country_filter_si.id = country_filter_sci.source_item_id
      WHERE country_filter_sci.story_cluster_id = ranked.story_cluster_id
        AND lower(country_filter_si.country) = lower(${add(query.country)})
    )`);
    if (query.language) conditions.push(`EXISTS (
      SELECT 1 FROM story_cluster_items language_filter_sci
      JOIN source_items language_filter_si ON language_filter_si.id = language_filter_sci.source_item_id
      WHERE language_filter_sci.story_cluster_id = ranked.story_cluster_id
        AND lower(language_filter_si.language) = lower(${add(query.language)})
    )`);
    if (query.verification) conditions.push(`ranked.verification = ${add(query.verification)}`);
    if (query.search) {
      const search = `%${query.search.replace(/[\\%_]/g, (value) => `\\${value}`)}%`;
      conditions.push(`(
        ranked.title ILIKE ${add(search)} ESCAPE '\\'
        OR ranked.brief ILIKE ${add(search)} ESCAPE '\\'
        OR ranked.topic_key ILIKE ${add(search)} ESCAPE '\\'
        OR EXISTS (
          SELECT 1 FROM story_cluster_items search_sci
          JOIN source_items search_si ON search_si.id = search_sci.source_item_id
          WHERE search_sci.story_cluster_id = ranked.story_cluster_id
            AND (search_si.title ILIKE ${add(search)} ESCAPE '\\'
              OR search_si.summary ILIKE ${add(search)} ESCAPE '\\'
              OR search_si.author ILIKE ${add(search)} ESCAPE '\\'
              OR search_si.topic_key ILIKE ${add(search)} ESCAPE '\\')
        )
      )`);
    }
    if (query.freshness && query.freshness !== "any") {
      const interval = {
        lastHour: "1 hour",
        lastDay: "1 day",
        lastThreeDays: "3 days",
        lastWeek: "7 days",
      }[query.freshness];
      conditions.push(`ranked.latest_published_at >= now() - interval '${interval}'`);
    }
    if (query.cursor) {
      const cursor = decodeReadCursor(query.cursor, "opportunity", sort);
      const primary = sort === "newest" ? undefined : add(cursor.primary);
      const secondary = add(cursor.secondary);
      const timestamp = add(cursor.timestamp);
      if (sort === "totalScore") {
        conditions.push(`(
          ranked.rank_score < ${primary}
          OR (ranked.rank_score = ${primary} AND (
            ranked.latest_published_at < ${timestamp}::timestamptz
            OR (ranked.latest_published_at = ${timestamp}::timestamptz AND ranked.id > ${add(cursor.id)})
          ))
        )`);
      } else if (sort === "newest") {
        conditions.push(`(
          ranked.latest_published_at < ${timestamp}::timestamptz
          OR (ranked.latest_published_at = ${timestamp}::timestamptz AND (
            ranked.rank_score < ${secondary}
            OR (ranked.rank_score = ${secondary} AND ranked.id > ${add(cursor.id)})
          ))
        )`);
      } else {
        const sortField = sort === "highPriority"
          ? "ranked.high_priority::int"
          : sort === "regionalRelevance"
            ? "ranked.regional_relevance_score"
            : "ranked.arabic_coverage_gap_score";
        conditions.push(`(
          ${sortField} < ${primary}
          OR (${sortField} = ${primary} AND (
            ranked.rank_score < ${secondary}
            OR (ranked.rank_score = ${secondary} AND (
              ranked.latest_published_at < ${timestamp}::timestamptz
              OR (ranked.latest_published_at = ${timestamp}::timestamptz AND ranked.id > ${add(cursor.id)})
            ))
          ))
        )`);
      }
    }
    const order = sort === "totalScore"
      ? "ranked.rank_score DESC, ranked.latest_published_at DESC, ranked.id ASC"
      : sort === "newest"
        ? "ranked.latest_published_at DESC, ranked.rank_score DESC, ranked.id ASC"
        : sort === "highPriority"
          ? "ranked.high_priority DESC, ranked.rank_score DESC, ranked.latest_published_at DESC, ranked.id ASC"
          : sort === "regionalRelevance"
            ? "ranked.regional_relevance_score DESC, ranked.rank_score DESC, ranked.latest_published_at DESC, ranked.id ASC"
            : "ranked.arabic_coverage_gap_score DESC, ranked.rank_score DESC, ranked.latest_published_at DESC, ranked.id ASC";
    const limit = Math.min(query.limit ?? 50, 200);
    const limitParam = add(limit + 1);
    const result = await this.database.query<OpportunityRow>(`
      WITH ranked AS (
        SELECT o.*, sc.topic_key, sc.verification, sc.earliest_published_at, sc.original_source_item_id,
          activity.latest_published_at,
          activity.latest_published_at::text AS latest_published_at_text,
          (o.freshness_score + o.credibility_score + o.momentum_score + o.creator_activity_score
            + o.arabic_coverage_gap_score + o.regional_relevance_score) AS rank_score,
          ((o.freshness_score + o.credibility_score + o.momentum_score + o.creator_activity_score
            + o.arabic_coverage_gap_score + o.regional_relevance_score) >= 75
            AND sc.verification = 'Confirmed') AS high_priority
        FROM opportunities o
        JOIN story_clusters sc ON sc.id = o.story_cluster_id
        LEFT JOIN LATERAL (
          SELECT COALESCE(MAX(si.published_at), sc.earliest_published_at) AS latest_published_at
          FROM story_cluster_items sci
          JOIN source_items si ON si.id = sci.source_item_id
          WHERE sci.story_cluster_id = sc.id
        ) activity ON true
      )
      SELECT * FROM ranked
      ${conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : ""}
      ORDER BY ${order}
      LIMIT ${limitParam}
    `, values);
    const hasNext = result.rows.length > limit;
    const rows = hasNext ? result.rows.slice(0, limit) : result.rows;
    const items = await this.hydrateOpportunities(rows);
    const last = rows[rows.length - 1];
    if (!last || !hasNext) return { items, nextCursor: null };
    return {
      items,
      nextCursor: encodeReadCursor(opportunityCursor(last, sort)),
    };
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

  async updateOpportunityDisposition(
    id: string,
    mutation: OpportunityDispositionMutation,
  ): Promise<OpportunityDispositionState | null> {
    const client = await this.database.connect();
    try {
      await client.query("BEGIN");
      const currentResult = await client.query<{
        disposition: OpportunityDisposition;
        disposition_updated_at: Date;
        disposition_mutation_id: string | null;
      }>(`
        SELECT disposition, disposition_updated_at, disposition_mutation_id
        FROM opportunities
        WHERE id = $1
        FOR UPDATE
      `, [id]);
      const current = currentResult.rows[0];
      if (!current) {
        await client.query("COMMIT");
        return null;
      }
      const normalizedMutationID = mutation.mutationID.toLowerCase();
      const isSameMutation = current.disposition_mutation_id === normalizedMutationID;
      const incomingTime = new Date(mutation.changedAt).getTime();
      const currentTime = current.disposition_updated_at.getTime();
      const wins = current.disposition_mutation_id === null
        || isSameMutation
        || incomingTime > currentTime
        || (incomingTime === currentTime && current.disposition_mutation_id < normalizedMutationID);
      if (wins && !isSameMutation) {
        await client.query(`
          UPDATE opportunities
          SET disposition = $2,
              disposition_updated_at = $3,
              disposition_mutation_id = $4,
              updated_at = now()
          WHERE id = $1
        `, [id, mutation.disposition, mutation.changedAt, normalizedMutationID]);
      }
      await client.query("COMMIT");
      return {
        opportunityID: id,
        disposition: wins && !isSameMutation ? mutation.disposition : current.disposition,
        changedAt: wins && !isSameMutation
          ? new Date(mutation.changedAt).toISOString()
          : current.disposition_updated_at.toISOString(),
        mutationID: wins && !isSameMutation ? normalizedMutationID : current.disposition_mutation_id!,
        outcome: isSameMutation ? "idempotent" : wins ? "applied" : "superseded",
      };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
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

  async updateWatchlist(id: string, input: Omit<WatchlistEntry, "id">): Promise<WatchlistEntry | null> {
    const result = await this.database.query<{ id: string }>(`
      UPDATE watchlist_entries
      SET kind = $2, value = $3, high_priority = $4
      WHERE id = $1
      RETURNING id
    `, [id, input.kind, input.value, input.highPriority]);
    return result.rows[0] ? { id: result.rows[0].id, ...input } : null;
  }

  async replaceWatchlist(entries: WatchlistEntry[]): Promise<WatchlistEntry[]> {
    const client = await this.database.connect();
    try {
      await client.query("BEGIN");
      const ids = entries.map((entry) => entry.id);
      if (ids.length === 0) {
        await client.query("DELETE FROM watchlist_entries");
      } else {
        await client.query("DELETE FROM watchlist_entries WHERE id <> ALL($1::uuid[])", [ids]);
      }
      for (const entry of entries) {
        await client.query(`
          INSERT INTO watchlist_entries (id, kind, value, high_priority)
          VALUES ($1, $2, $3, $4)
          ON CONFLICT (id) DO UPDATE SET
            kind = EXCLUDED.kind,
            value = EXCLUDED.value,
            high_priority = EXCLUDED.high_priority
        `, [entry.id, entry.kind, entry.value, entry.highPriority]);
      }
      await client.query("COMMIT");
      return this.listWatchlist();
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
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

  async listNotificationsPage(query: NotificationReadQuery): Promise<ReadPage<NotificationRecord>> {
    const values: unknown[] = [];
    const conditions: string[] = [];
    const add = (value: unknown): string => {
      values.push(value);
      return `$${values.length}`;
    };
    if (query.isRead !== undefined) conditions.push(`n.is_read = ${add(query.isRead)}`);
    if (query.delivery) conditions.push(`n.delivery = ${add(query.delivery)}`);
    if (query.search) {
      const search = `%${query.search.replace(/[\\%_]/g, (value) => `\\${value}`)}%`;
      conditions.push(`(
        n.title ILIKE ${add(search)} ESCAPE '\\'
        OR EXISTS (
          SELECT 1 FROM opportunities notification_search_o
          WHERE notification_search_o.id = n.opportunity_id
            AND (notification_search_o.title ILIKE ${add(search)} ESCAPE '\\'
              OR notification_search_o.brief ILIKE ${add(search)} ESCAPE '\\')
        )
      )`);
    }
    if (query.cursor) {
      const cursor = decodeReadCursor(query.cursor, "notification", "createdAt");
      const createdAt = add(cursor.timestamp);
      conditions.push(`(n.created_at < ${createdAt}::timestamptz OR (n.created_at = ${createdAt}::timestamptz AND n.id > ${add(cursor.id)}))`);
    }
    const limit = Math.min(query.limit ?? 50, 200);
    const limitParam = add(limit + 1);
    const result = await this.database.query<{
      id: string;
      opportunity_id: string;
      title: string;
      delivery: NotificationRecord["delivery"];
      created_at: Date;
      created_at_text: string;
      is_read: boolean;
    }>(`
      SELECT n.id, n.opportunity_id, n.title, n.delivery, n.created_at, n.created_at::text AS created_at_text, n.is_read
      FROM notifications n
      ${conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : ""}
      ORDER BY n.created_at DESC, n.id ASC
      LIMIT ${limitParam}
    `, values);
    const hasNext = result.rows.length > limit;
    const rows = hasNext ? result.rows.slice(0, limit) : result.rows;
    const items = rows.map(mapNotification);
    const last = rows[rows.length - 1];
    return {
      items,
      nextCursor: last && hasNext
        ? encodeReadCursor({
          kind: "notification",
          sort: "createdAt",
          primary: 0,
          secondary: 0,
          timestamp: last.created_at_text,
          id: last.id,
        })
        : null,
    };
  }

  async listTopics(query: TopicReadQuery): Promise<ReadPage<Topic>> {
    const values: unknown[] = [];
    const conditions: string[] = [];
    const add = (value: unknown): string => {
      values.push(value);
      return `$${values.length}`;
    };
    if (query.search) {
      const search = `%${query.search.replace(/[\\%_]/g, (value) => `\\${value}`)}%`;
      conditions.push(`(topic_key ILIKE ${add(search)} ESCAPE '\\' OR title ILIKE ${add(search)} ESCAPE '\\')`);
    }
    if (query.cursor) {
      const cursor = decodeReadCursor(query.cursor, "topic", "latestActivityAt");
      const latest = add(cursor.timestamp);
      conditions.push(`(latest_activity_at < ${latest}::timestamptz OR (latest_activity_at = ${latest}::timestamptz AND topic_key > ${add(cursor.id)}))`);
    }
    const limit = Math.min(query.limit ?? 50, 200);
    const limitParam = add(limit + 1);
    const result = await this.database.query<{
      topic_key: string;
      title: string;
      opportunity_count: string;
      latest_published_at: Date;
      latest_activity_at: Date;
      latest_activity_at_text: string;
      confirmed_count: string;
      disputed_count: string;
      unverified_count: string;
    }>(`
      WITH topic_rows AS (
        SELECT sc.topic_key,
          (ARRAY_AGG(o.title ORDER BY GREATEST(o.updated_at, sc.updated_at, COALESCE(activity.latest_collected_at, to_timestamp(0))) DESC, o.title ASC))[1] AS title,
          COUNT(*) AS opportunity_count,
          MAX(sc.earliest_published_at) AS latest_published_at,
          MAX(GREATEST(o.updated_at, sc.updated_at, COALESCE(activity.latest_collected_at, to_timestamp(0)))) AS latest_activity_at,
          COUNT(*) FILTER (WHERE sc.verification = 'Confirmed') AS confirmed_count,
          COUNT(*) FILTER (WHERE sc.verification = 'Disputed') AS disputed_count,
          COUNT(*) FILTER (WHERE sc.verification = 'Unverified') AS unverified_count
        FROM opportunities o
        JOIN story_clusters sc ON sc.id = o.story_cluster_id
        LEFT JOIN LATERAL (
          SELECT MAX(si.collected_at) AS latest_collected_at
          FROM story_cluster_items sci
          JOIN source_items si ON si.id = sci.source_item_id
          WHERE sci.story_cluster_id = sc.id
        ) activity ON true
        GROUP BY sc.topic_key
      )
      SELECT topic_rows.*, latest_activity_at::text AS latest_activity_at_text FROM topic_rows
      ${conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : ""}
      ORDER BY latest_activity_at DESC, topic_key ASC
      LIMIT ${limitParam}
    `, values);
    const hasNext = result.rows.length > limit;
    const rows = hasNext ? result.rows.slice(0, limit) : result.rows;
    return {
      items: rows.map(mapTopic),
      nextCursor: rows.length > 0 && hasNext
        ? encodeReadCursor({
          kind: "topic",
          sort: "latestActivityAt",
          primary: 0,
          secondary: 0,
          timestamp: rows[rows.length - 1]!.latest_activity_at_text,
          id: rows[rows.length - 1]!.topic_key,
        })
        : null,
    };
  }

  async getTopic(topicKey: string): Promise<Omit<TopicDetail, "serverTime"> | null> {
    const result = await this.database.query<{
      topic_key: string;
      title: string;
      opportunity_count: string;
      latest_published_at: Date;
      latest_activity_at: Date;
      confirmed_count: string;
      disputed_count: string;
      unverified_count: string;
    }>(`
      SELECT sc.topic_key,
        (ARRAY_AGG(o.title ORDER BY GREATEST(o.updated_at, sc.updated_at, COALESCE(activity.latest_collected_at, to_timestamp(0))) DESC, o.title ASC))[1] AS title,
        COUNT(*) AS opportunity_count,
        MAX(sc.earliest_published_at) AS latest_published_at,
        MAX(GREATEST(o.updated_at, sc.updated_at, COALESCE(activity.latest_collected_at, to_timestamp(0)))) AS latest_activity_at,
        COUNT(*) FILTER (WHERE sc.verification = 'Confirmed') AS confirmed_count,
        COUNT(*) FILTER (WHERE sc.verification = 'Disputed') AS disputed_count,
        COUNT(*) FILTER (WHERE sc.verification = 'Unverified') AS unverified_count
      FROM opportunities o
      JOIN story_clusters sc ON sc.id = o.story_cluster_id
      LEFT JOIN LATERAL (
        SELECT MAX(si.collected_at) AS latest_collected_at
        FROM story_cluster_items sci
        JOIN source_items si ON si.id = sci.source_item_id
        WHERE sci.story_cluster_id = sc.id
      ) activity ON true
      WHERE sc.topic_key = $1
      GROUP BY sc.topic_key
    `, [topicKey]);
    const topic = result.rows[0] ? mapTopic(result.rows[0]) : null;
    if (!topic) return null;
    const opportunities = await this.listOpportunitiesPage({ topic: topicKey, limit: 100, sort: "newest" });
    return { ...topic, opportunities: opportunities.items };
  }

  async listComments(): Promise<{ page: ReadPage<CommentProjection>; availability: CommentsAvailability }> {
    const result = await this.database.query<{
      source_group: "Comments";
      connection_state: CommentsAvailability["state"];
      data_truth: CommentsAvailability["dataTruth"];
      evidence: string;
      repair_action: string;
    }>(`
      SELECT source_group, connection_state, data_truth, evidence, repair_action
      FROM source_health
      WHERE source_group = 'Comments'
    `);
    const row = result.rows[0];
    return {
      page: { items: [], nextCursor: null },
      availability: row
        ? {
          group: "Comments",
          state: row.connection_state,
          dataTruth: row.data_truth,
          evidence: row.evidence,
          repairAction: row.repair_action,
        }
        : {
          group: "Comments",
          state: "Unavailable",
          dataTruth: "Unavailable",
          evidence: "Comments source health is unavailable.",
          repairAction: "Check the backend source-health record.",
        },
    };
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
      UPDATE notifications SET is_read = $2, updated_at = now()
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

  async remove(key: string): Promise<void> {
    await this.database.query("DELETE FROM encrypted_configs WHERE config_key = $1", [key]);
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
        dispositionUpdatedAt: row.disposition_updated_at.toISOString(),
        dispositionMutationID: row.disposition_mutation_id,
        isHighPriority: total >= 75 && row.verification === "Confirmed",
      };
    });
  }
}

function opportunityCursor(row: OpportunityRow, sort: string): ReadCursor {
  const latest = row.latest_published_at ?? row.earliest_published_at;
  const timestamp = row.latest_published_at_text ?? latest.toISOString();
  const rank = row.rank_score ?? (
    row.freshness_score + row.credibility_score + row.momentum_score
      + row.creator_activity_score + row.arabic_coverage_gap_score + row.regional_relevance_score
  );
  if (sort === "newest") {
    return { kind: "opportunity", sort, primary: 0, secondary: rank, timestamp, id: row.id };
  }
  if (sort === "highPriority") {
    return {
      kind: "opportunity", sort, primary: row.high_priority ? 1 : 0, secondary: rank,
      timestamp, id: row.id,
    };
  }
  if (sort === "regionalRelevance") {
    return {
      kind: "opportunity", sort, primary: row.regional_relevance_score ?? 0, secondary: rank,
      timestamp, id: row.id,
    };
  }
  if (sort === "arabicCoverageGap") {
    return {
      kind: "opportunity", sort, primary: row.arabic_coverage_gap_score ?? 0, secondary: rank,
      timestamp, id: row.id,
    };
  }
  return { kind: "opportunity", sort: "totalScore", primary: rank, secondary: 0, timestamp, id: row.id };
}

function mapNotification(row: {
  id: string;
  opportunity_id: string;
  title: string;
  delivery: NotificationRecord["delivery"];
  created_at: Date;
  is_read: boolean;
}): NotificationRecord {
  return {
    id: row.id,
    opportunityID: row.opportunity_id,
    title: row.title,
    delivery: row.delivery,
    createdAt: row.created_at.toISOString(),
    isRead: row.is_read,
  };
}

function mapPreferences(row: {
  refresh_minutes: number;
  notifications_enabled: boolean;
  digest_hour: number;
  quiet_hours_enabled: boolean;
  quiet_hours_start: string;
  quiet_hours_end: string;
  locale: string;
  time_zone: string;
  updated_at: Date;
  version: string;
}): PreferenceRecord {
  return {
    refreshMinutes: row.refresh_minutes,
    notificationsEnabled: row.notifications_enabled,
    digestHour: row.digest_hour,
    quietHours: {
      enabled: row.quiet_hours_enabled,
      start: row.quiet_hours_start,
      end: row.quiet_hours_end,
    },
    locale: row.locale,
    timeZone: row.time_zone,
    updatedAt: row.updated_at.toISOString(),
    etag: `"preferences-v${row.version}"`,
  };
}

function normalizeETag(value: string): string {
  return value.trim().replace(/^W\//, "");
}

function mapTopic(row: {
  topic_key: string;
  title: string;
  opportunity_count: string;
  latest_published_at: Date;
  latest_activity_at: Date;
  confirmed_count: string;
  disputed_count: string;
  unverified_count: string;
}): Topic {
  const age = Date.now() - row.latest_published_at.getTime();
  const freshness = age <= 3_600_000
    ? "lastHour"
    : age <= 86_400_000
      ? "lastDay"
      : age <= 3 * 86_400_000
        ? "lastThreeDays"
        : age <= 7 * 86_400_000
          ? "lastWeek"
          : "older";
  return {
    topicKey: row.topic_key,
    title: row.title,
    opportunityCount: Number(row.opportunity_count),
    freshness,
    verificationMix: {
      confirmed: Number(row.confirmed_count),
      disputed: Number(row.disputed_count),
      unverified: Number(row.unverified_count),
    },
    latestPublishedAt: row.latest_published_at.toISOString(),
    latestActivityAt: row.latest_activity_at.toISOString(),
  };
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
