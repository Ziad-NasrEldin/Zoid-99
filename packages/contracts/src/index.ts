import { z } from "zod";

export const apiVersion = "v1" as const;

export const sourceGroups = [
  "YouTube",
  "Google Trends",
  "Instagram",
  "Comments",
  "US & Official",
  "X",
] as const;
export const verificationStates = ["Confirmed", "Disputed", "Unverified"] as const;
export const connectionStates = [
  "Connected",
  "Setup required",
  "Disconnected",
  "Unavailable",
  "Rate limited",
  "Delayed",
  "Cached",
  "Unsupported",
] as const;
export const sourceHealthStates = [
  "Connected",
  "Setup required",
  "Unavailable",
  "Rate limited",
  "Delayed",
] as const;
export const dataTruthValues = [
  "Live",
  "Cached",
  "Missing",
  "Delayed",
  "Unavailable",
  "Rate limited",
] as const;
export const opportunityDispositions = ["active", "saved", "watched", "dismissed", "muted"] as const;
export const notificationDeliveries = ["Immediate", "Digest"] as const;
export const watchlistKinds = [
  "Creator",
  "Official source",
  "Company",
  "Keyword",
  "Topic",
  "Country",
  "Language",
] as const;
export const serverProviders = ["google-trends", "ai-provider"] as const;

export type SourceGroup = (typeof sourceGroups)[number];
export type VerificationState = (typeof verificationStates)[number];
export type ConnectionState = (typeof connectionStates)[number];
export type SourceHealthState = (typeof sourceHealthStates)[number];
export type DataTruth = (typeof dataTruthValues)[number];
export type OpportunityDisposition = (typeof opportunityDispositions)[number];
export type NotificationDelivery = (typeof notificationDeliveries)[number];
export type WatchlistKind = (typeof watchlistKinds)[number];
export type ServerProvider = (typeof serverProviders)[number];

const uuidSchema = z.string().uuid();
const isoDateSchema = z.iso.datetime({ offset: true });

export const dispositionSchema = z.enum(opportunityDispositions);
export const sourceGroupSchema = z.enum(sourceGroups);
export const verificationStateSchema = z.enum(verificationStates);
export const connectionStateSchema = z.enum(connectionStates);
export const sourceHealthStateSchema = z.enum(sourceHealthStates);
export const dataTruthSchema = z.enum(dataTruthValues);
export const notificationDeliverySchema = z.enum(notificationDeliveries);
export const watchlistKindSchema = z.enum(watchlistKinds);
export const serverProviderSchema = z.enum(serverProviders);

const timeOfDaySchema = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
const localeSchema = z.string().trim().regex(/^[a-z]{2}(?:-[A-Z]{2})?$/);
const timeZoneSchema = z.string().trim().min(1).max(100).regex(/^(UTC|[A-Za-z_]+(?:\/[A-Za-z0-9_+.-]+)+)$/);

export const sourceItemSchema = z.object({
  id: uuidSchema,
  group: sourceGroupSchema,
  externalID: z.string().min(1),
  title: z.string(),
  summary: z.string(),
  author: z.string(),
  url: z.string().url(),
  publishedAt: isoDateSchema,
  collectedAt: isoDateSchema,
  language: z.string(),
  country: z.string(),
  topicKey: z.string(),
  isOriginalSource: z.boolean(),
  credibility: z.number(),
  engagement: z.number(),
  verification: verificationStateSchema,
}).strict();

export const sourceItemInputSchema = sourceItemSchema.omit({ id: true });

export const scoreBreakdownSchema = z.object({
  freshness: z.number(),
  credibility: z.number(),
  momentum: z.number(),
  creatorActivity: z.number(),
  arabicCoverageGap: z.number(),
  regionalRelevance: z.number(),
}).strict();

export const opportunitySchema = z.object({
  id: uuidSchema,
  topicKey: z.string(),
  title: z.string(),
  brief: z.string(),
  verification: verificationStateSchema,
  earliestPublishedAt: isoDateSchema,
  originalSource: sourceItemSchema.nullable(),
  items: z.array(sourceItemSchema),
  score: scoreBreakdownSchema,
  regionalExplanation: z.string(),
  coverageExplanation: z.string(),
  disposition: dispositionSchema,
  dispositionUpdatedAt: isoDateSchema,
  dispositionMutationID: uuidSchema.nullable(),
  isHighPriority: z.boolean(),
}).strict();

export const opportunityInputSchema = opportunitySchema.pick({
  title: true,
  brief: true,
  score: true,
  regionalExplanation: true,
  coverageExplanation: true,
  disposition: true,
}).strict();

export const watchlistFieldsSchema = z.object({
  kind: watchlistKindSchema,
  value: z.string().trim().min(1).max(500),
  highPriority: z.boolean(),
}).strict();

export const watchlistSchema = z.object({
  id: uuidSchema,
  ...watchlistFieldsSchema.shape,
  serverTime: isoDateSchema.optional(),
}).strict();

export const watchlistInputSchema = watchlistFieldsSchema;
export const watchlistReplacementSchema = z.object({
  entries: z.array(watchlistSchema).max(2_000),
}).strict();

export const notificationSchema = z.object({
  id: uuidSchema,
  opportunityID: uuidSchema,
  title: z.string(),
  delivery: notificationDeliverySchema,
  createdAt: isoDateSchema,
  isRead: z.boolean(),
  serverTime: isoDateSchema.optional(),
}).strict();

export const notificationInputSchema = notificationSchema.omit({ id: true, opportunityID: true });
export const notificationReadSchema = z.object({ isRead: z.boolean() }).strict();

export const sourceHealthSchema = z.object({
  group: sourceGroupSchema,
  state: connectionStateSchema,
  lastActivity: isoDateSchema.nullable(),
  evidence: z.string().min(1),
  repairAction: z.string().min(1),
  dataTruth: dataTruthSchema,
}).strict();

export const sourceHealthIngestionSchema = z.object({
  group: sourceGroupSchema,
  state: sourceHealthStateSchema,
  lastActivity: isoDateSchema.nullable().optional().transform((value) => value ?? null),
  evidence: z.string().min(1),
  repairAction: z.string().min(1),
  dataTruth: dataTruthSchema,
}).strict();

export const connectionSchema = z.object({
  provider: serverProviderSchema,
  state: connectionStateSchema,
  lastActivity: isoDateSchema.nullable(),
  evidence: z.string().min(1),
  repairAction: z.string().min(1),
  retryAt: isoDateSchema.nullable(),
}).strict();

export const bootstrapSchema = z.object({
  sourceHealth: z.array(sourceHealthSchema),
  opportunities: z.array(opportunitySchema),
  watchlist: z.array(watchlistSchema),
  notifications: z.array(notificationSchema),
}).strict();

export const paginationQuerySchema = z.object({
  cursor: z.string().trim().min(1).max(512).optional(),
  limit: z.coerce.number().int().min(1).max(200).optional(),
}).strict();

export const freshnessValues = ["any", "lastHour", "lastDay", "lastThreeDays", "lastWeek"] as const;
export const opportunitySortValues = [
  "totalScore",
  "newest",
  "highPriority",
  "regionalRelevance",
  "arabicCoverageGap",
] as const;
export const topicFreshnessValues = ["lastHour", "lastDay", "lastThreeDays", "lastWeek", "older"] as const;

export const opportunityReadQuerySchema = paginationQuerySchema.extend({
  disposition: dispositionSchema.optional(),
  source: sourceGroupSchema.optional(),
  topic: z.string().trim().min(1).max(200).optional(),
  country: z.string().trim().min(1).max(100).optional(),
  language: z.string().trim().min(1).max(100).optional(),
  verification: verificationStateSchema.optional(),
  freshness: z.enum(freshnessValues).optional(),
  search: z.string().trim().min(1).max(200).optional(),
  sort: z.enum(opportunitySortValues).optional(),
}).strict();

export const notificationReadQuerySchema = paginationQuerySchema.extend({
  isRead: z.preprocess((value) => {
    if (value === "true" || value === true) return true;
    if (value === "false" || value === false) return false;
    return value;
  }, z.boolean().optional()),
  delivery: notificationDeliverySchema.optional(),
  search: z.string().trim().min(1).max(200).optional(),
}).strict();

export const topicReadQuerySchema = paginationQuerySchema.extend({
  search: z.string().trim().min(1).max(200).optional(),
}).strict();

export const paginationSchema = z.object({
  nextCursor: z.string().nullable(),
}).strict();

export function paginatedResponseSchema<T extends z.ZodType>(itemSchema: T) {
  return z.object({
    items: z.array(itemSchema),
    nextCursor: z.string().nullable(),
    serverTime: isoDateSchema,
  }).strict();
}

export type PaginatedResponse<T> = {
  items: T[];
  nextCursor: string | null;
  serverTime: string;
};

export const verificationMixSchema = z.object({
  confirmed: z.number().int().nonnegative(),
  disputed: z.number().int().nonnegative(),
  unverified: z.number().int().nonnegative(),
}).strict();

export const topicSchema = z.object({
  topicKey: z.string().min(1),
  title: z.string().min(1),
  opportunityCount: z.number().int().nonnegative(),
  freshness: z.enum(topicFreshnessValues),
  verificationMix: verificationMixSchema,
  latestPublishedAt: isoDateSchema,
  latestActivityAt: isoDateSchema,
}).strict();

export const topicDetailSchema = topicSchema.extend({
  opportunities: z.array(opportunitySchema).max(100),
  serverTime: isoDateSchema,
}).strict();

export const commentsAvailabilitySchema = z.object({
  group: z.literal("Comments"),
  state: connectionStateSchema,
  dataTruth: dataTruthSchema,
  evidence: z.string().min(1),
  repairAction: z.string().min(1),
}).strict();

export const commentProjectionSchema = z.object({
  id: uuidSchema,
  question: z.string(),
  count: z.number().int().nonnegative(),
  demand: z.string(),
  language: z.string(),
  sourceItems: z.array(sourceItemSchema),
}).strict();

export const commentsResponseSchema = z.object({
  items: z.array(commentProjectionSchema),
  nextCursor: z.string().nullable(),
  serverTime: isoDateSchema,
  availability: commentsAvailabilitySchema,
}).strict();

export const dispositionMutationSchema = z.object({
  disposition: dispositionSchema,
  changedAt: isoDateSchema,
  mutationID: uuidSchema,
}).strict();

export const mutationEnvelopeSchema = z.object({
  mutationID: uuidSchema,
  serverTime: isoDateSchema,
}).strict();

export const quietHoursSchema = z.object({
  enabled: z.boolean(),
  start: timeOfDaySchema,
  end: timeOfDaySchema,
}).strict();

export const preferencesSchema = z.object({
  refreshMinutes: z.number().int().min(5).max(60),
  notificationsEnabled: z.boolean(),
  digestHour: z.number().int().min(0).max(23),
  quietHours: quietHoursSchema,
  locale: localeSchema,
  timeZone: timeZoneSchema,
  updatedAt: isoDateSchema,
}).strict();

export const preferencesPatchSchema = z.object({
  refreshMinutes: z.number().int().min(5).max(60).optional(),
  notificationsEnabled: z.boolean().optional(),
  digestHour: z.number().int().min(0).max(23).optional(),
  quietHours: quietHoursSchema.optional(),
  locale: localeSchema.optional(),
  timeZone: timeZoneSchema.optional(),
}).strict().refine((value) => Object.keys(value).length > 0, {
  message: "At least one preference must be supplied",
});

export const opportunityDispositionStateSchema = z.object({
  opportunityID: uuidSchema,
  disposition: dispositionSchema,
  changedAt: isoDateSchema,
  mutationID: uuidSchema,
  outcome: z.enum(["applied", "idempotent", "superseded"]),
  serverTime: isoDateSchema.optional(),
}).strict();

export const errorCodes = [
  "unauthorized",
  "service_unavailable",
  "invalid_request",
  "not_found",
  "conflict",
  "payload_too_large",
  "rate_limited",
  "internal_error",
] as const;
export const errorCodeSchema = z.enum(errorCodes);
export const errorDetailSchema = z.object({
  path: z.string(),
  message: z.string(),
}).strict();
export const structuredErrorSchema = z.object({
  error: errorCodeSchema,
  message: z.string(),
  requestId: z.string().min(1).optional(),
  details: z.array(errorDetailSchema).optional(),
}).strict();

export const originalSourceSchema = z.object({
  group: sourceGroupSchema,
  externalID: z.string().min(1),
}).strict();

export const researchBatchSchema = z.object({
  clusterKey: z.string(),
  topicKey: z.string(),
  verification: verificationStateSchema,
  originState: z.enum(["Identified", "Unknown"]),
  originalSource: originalSourceSchema.nullable(),
  sourceItems: z.array(sourceItemInputSchema).min(1),
  opportunity: opportunityInputSchema,
  notification: notificationInputSchema.nullable(),
}).strict();

export const ingestionSchema = z.object({
  sourceHealth: z.array(sourceHealthIngestionSchema).min(1),
  batches: z.array(researchBatchSchema),
}).strict();

export type SourceItem = z.infer<typeof sourceItemSchema>;
export type ScoreBreakdown = z.infer<typeof scoreBreakdownSchema>;
export type Opportunity = z.infer<typeof opportunitySchema>;
export type WatchlistEntry = z.infer<typeof watchlistSchema>;
export type NotificationRecord = z.infer<typeof notificationSchema>;
export type SourceHealth = z.infer<typeof sourceHealthSchema>;
export type SourceHealthIngestion = z.infer<typeof sourceHealthIngestionSchema>;
export type ConnectionStatus = z.infer<typeof connectionSchema>;
export type BootstrapPayload = z.infer<typeof bootstrapSchema>;
export type OpportunityDispositionMutation = z.infer<typeof dispositionMutationSchema>;
export type MutationEnvelope = z.infer<typeof mutationEnvelopeSchema>;
export type QuietHours = z.infer<typeof quietHoursSchema>;
export type Preferences = z.infer<typeof preferencesSchema>;
export type PreferencesPatch = z.infer<typeof preferencesPatchSchema>;
export type OpportunityDispositionState = z.infer<typeof opportunityDispositionStateSchema>;
export type ResearchBatch = z.infer<typeof researchBatchSchema>;
export type IngestionPayload = z.infer<typeof ingestionSchema>;
export type StructuredError = z.infer<typeof structuredErrorSchema>;
export type OpportunityReadQuery = z.infer<typeof opportunityReadQuerySchema>;
export type NotificationReadQuery = z.infer<typeof notificationReadQuerySchema>;
export type TopicReadQuery = z.infer<typeof topicReadQuerySchema>;
export type Topic = z.infer<typeof topicSchema>;
export type TopicDetail = z.infer<typeof topicDetailSchema>;
export type CommentProjection = z.infer<typeof commentProjectionSchema>;
export type CommentsAvailability = z.infer<typeof commentsAvailabilitySchema>;
