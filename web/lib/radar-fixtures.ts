import type { Opportunity, Topic, TopicDetail } from "@zoid99/contracts";

export const radarOpportunityFixture: Opportunity = {
  id: "10000000-0000-4000-8000-000000000099",
  topicKey: "official-release-99",
  title: "Official release 99",
  brief: "Primary-source release evidence.",
  verification: "Confirmed",
  earliestPublishedAt: "2026-07-28T08:00:00.000Z",
  originalSource: {
    id: "20000000-0000-4000-8000-000000000099",
    group: "US & Official",
    externalID: "official-entry-99",
    title: "Official release 99",
    summary: "Primary-source release evidence.",
    author: "Official publisher",
    url: "https://official.example/releases/99",
    publishedAt: "2026-07-28T08:00:00.000Z",
    collectedAt: "2026-07-28T08:05:00.000Z",
    language: "en",
    country: "US",
    topicKey: "official-release-99",
    isOriginalSource: true,
    credibility: 1,
    engagement: 0,
    verification: "Confirmed",
  },
  items: [],
  score: {
    freshness: 20,
    credibility: 20,
    momentum: 4,
    creatorActivity: 0,
    arabicCoverageGap: 15,
    regionalRelevance: 7,
  },
  regionalExplanation: "Regional demand evidence is not yet available.",
  coverageExplanation: "No Arabic-language coverage appears in the evidence.",
  disposition: "active",
  dispositionUpdatedAt: "2026-07-28T08:05:00.000Z",
  dispositionMutationID: null,
  isHighPriority: true,
};

export const radarPageFixture = {
  items: [radarOpportunityFixture],
  nextCursor: "next-page-cursor",
  serverTime: "2026-07-28T08:10:00.000Z",
};

export const topicFixture: Topic = {
  topicKey: "official-release-99",
  title: "Official release 99",
  opportunityCount: 1,
  freshness: "lastHour",
  verificationMix: { confirmed: 1, disputed: 0, unverified: 0 },
  latestPublishedAt: "2026-07-28T08:00:00.000Z",
  latestActivityAt: "2026-07-28T08:05:00.000Z",
};

export const topicDetailFixture: TopicDetail = {
  ...topicFixture,
  opportunities: [radarOpportunityFixture],
  serverTime: "2026-07-28T08:10:00.000Z",
};
