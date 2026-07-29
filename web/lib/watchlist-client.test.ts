import { describe, expect, it, vi } from "vitest";
import {
  createWatchlistClient,
  duplicateWatchlistEntry,
  providerSupportForKind,
  validateWatchlistInput,
  watchlistKinds,
  type WatchlistFetcher,
} from "@/lib/watchlist-client";

const entry = {
  id: "00000000-0000-4000-8000-000000000001",
  kind: "Creator" as const,
  value: "UC1234567890",
  highPriority: true,
};

describe("watchlist client", () => {
  it("keeps the seven contract kinds and prevents case-insensitive duplicates", () => {
    expect(watchlistKinds).toHaveLength(7);
    expect(duplicateWatchlistEntry([entry], { kind: "Creator", value: " uc1234567890 " })).toBe(true);
    expect(duplicateWatchlistEntry([entry], { kind: "Keyword", value: "uc1234567890" })).toBe(false);
  });

  it("validates official sources before sending them to the gateway", () => {
    expect(validateWatchlistInput({ kind: "Official source", value: "http://example.com", highPriority: false })).toMatch(/HTTPS/);
    expect(validateWatchlistInput({ kind: "Official source", value: "not a URL", highPriority: false })).toMatch(/HTTPS/);
    expect(validateWatchlistInput({ kind: "Official source", value: "https://example.com/releases", highPriority: false })).toBeNull();
  });

  it("reads real gateway data and sends an idempotent add mutation", async () => {
    const fetcher = vi.fn<WatchlistFetcher>();
    fetcher
      .mockResolvedValueOnce(new Response(JSON.stringify([entry]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ ...entry, serverTime: "2026-07-28T12:00:00.000Z" }), { status: 201 }));
    const client = createWatchlistClient(fetcher);

    await expect(client.list()).resolves.toEqual([entry]);
    await expect(client.add({ kind: entry.kind, value: entry.value, highPriority: true }, "watchlist-test-key")).resolves.toMatchObject(entry);

    expect(fetcher).toHaveBeenNthCalledWith(1, "/api/gateway/watchlist", expect.objectContaining({ method: "GET", cache: "no-store" }));
    expect(fetcher).toHaveBeenNthCalledWith(2, "/api/gateway/watchlist", expect.objectContaining({
      method: "POST",
      cache: "no-store",
      headers: expect.objectContaining({ "Idempotency-Key": "watchlist-test-key" }),
      body: JSON.stringify({ kind: "Creator", value: "UC1234567890", highPriority: true }),
    }));
  });

  it("reports provider truth instead of implying unsupported connectors are live", () => {
    expect(providerSupportForKind("Creator")).toBe("YouTube + X + Instagram");
    expect(providerSupportForKind("Language")).toBe("YouTube + X");
  });

  it("turns gateway transport failures into an unavailable client error", async () => {
    const fetcher = vi.fn<WatchlistFetcher>().mockRejectedValue(new Error("offline"));
    await expect(createWatchlistClient(fetcher).list()).rejects.toMatchObject({ kind: "unavailable", status: 503 });
  });
});
