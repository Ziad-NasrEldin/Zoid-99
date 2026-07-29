import { afterEach, describe, expect, it, vi } from "vitest";

import {
  buildRadarQuery,
  buildTopicsQuery,
  defaultRadarFilters,
  defaultTopicFilters,
  fetchRadarPage,
  fetchTopicDetail,
  fetchTopicsPage,
  parseRadarFilters,
  parseTopicFilters,
  serializeRadarFilters,
} from "@/lib/radar-client";
import { radarPageFixture, topicDetailFixture, topicFixture } from "@/lib/radar-fixtures";

afterEach(() => vi.restoreAllMocks());

describe("Radar query state", () => {
  it("keeps filters in a deterministic URL order and applies the bounded page size", () => {
    const filters = {
      ...defaultRadarFilters,
      search: "model release",
      source: "US & Official" as const,
      topic: "agents",
      country: "EG",
      language: "ar",
      freshness: "lastDay" as const,
      verification: "Confirmed" as const,
      disposition: "saved" as const,
      cursor: "cursor-1",
    };

    expect(buildRadarQuery(filters)).toBe("search=model+release&source=US+%26+Official&topic=agents&country=EG&language=ar&freshness=lastDay&verification=Confirmed&disposition=saved&cursor=cursor-1&limit=25");
    expect(parseRadarFilters(serializeRadarFilters(filters))).toEqual(filters);
  });

  it("drops unknown values and unsafe cursor lengths instead of sending them upstream", () => {
    const hugeCursor = "x".repeat(513);
    expect(parseRadarFilters(`source=not-a-source&verification=Unknown&cursor=${hugeCursor}`)).toEqual(defaultRadarFilters);
  });

  it("keeps topic search separate from topic detail selection", () => {
    expect(parseTopicFilters("search=agents&topic=official-release-99&cursor=page-2")).toEqual({
      search: "agents",
      topic: "official-release-99",
      cursor: "page-2",
    });
    expect(buildTopicsQuery(defaultTopicFilters)).toBe("limit=25");
  });
});

describe("gateway-backed research clients", () => {
  it("parses the paginated Radar response and includes the bounded query", async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => radarPageFixture });
    vi.stubGlobal("fetch", fetchMock);

    await expect(fetchRadarPage(defaultRadarFilters)).resolves.toEqual(radarPageFixture);
    expect(fetchMock).toHaveBeenCalledWith("/api/gateway/opportunities?limit=25", expect.objectContaining({ cache: "no-store" }));
  });

  it("uses server-computed Topics and topic evidence endpoints", async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({ ok: true, json: async () => ({ items: [topicFixture], nextCursor: null, serverTime: topicFixture.latestActivityAt }) })
      .mockResolvedValueOnce({ ok: true, json: async () => topicDetailFixture });
    vi.stubGlobal("fetch", fetchMock);

    await expect(fetchTopicsPage(defaultTopicFilters)).resolves.toMatchObject({ items: [topicFixture] });
    await expect(fetchTopicDetail(topicFixture.topicKey)).resolves.toEqual(topicDetailFixture);
    expect(fetchMock.mock.calls[0]?.[0]).toBe("/api/gateway/topics?limit=25");
    expect(fetchMock.mock.calls[1]?.[0]).toBe("/api/gateway/topics/official-release-99");
  });

  it("reports an honest unavailable state for gateway failures", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, json: async () => ({ msg: "Private gateway unavailable" }) }));

    await expect(fetchRadarPage(defaultRadarFilters)).rejects.toMatchObject({ message: "Private gateway unavailable", kind: "unavailable" });
  });
});
