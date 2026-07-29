import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it, vi } from "vitest";

import {
  getOpportunityData,
  getTodayData,
  updateOpportunityDisposition,
} from "@/lib/research-client";
import type { BootstrapPayload, OpportunityDispositionState } from "@zoid99/contracts";

const bootstrapFixture = JSON.parse(
  readFileSync(resolve(process.cwd(), "../packages/contracts/fixtures/bootstrap.json"), "utf8"),
) as BootstrapPayload;

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

describe("research gateway client", () => {
  it("loads Today from the authenticated gateway projection and preserves sync truth", async () => {
    const fetcher = vi.fn(async (path: string) => {
      expect(path).toBe("/bootstrap");
      return response(bootstrapFixture);
    });

    const today = await getTodayData(fetcher);

    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(today.opportunities[0]?.originalSource?.url).toBe("https://official.example/releases/99");
    expect(today.dataTruth).toBe("Live");
    expect(today.lastSuccessfulSync).toBe("2026-07-28T08:05:00.000Z");
  });

  it("labels a cached source projection instead of treating it as live", async () => {
    const cached = structuredClone(bootstrapFixture);
    cached.sourceHealth[0]!.dataTruth = "Cached";
    const today = await getTodayData(async () => response(cached));

    expect(today.dataTruth).toBe("Cached");
  });

  it("loads a detail projection through the gateway path", async () => {
    const opportunity = bootstrapFixture.opportunities[0]!;
    const fetcher = vi.fn(async (path: string) => {
      expect(path).toBe(`/opportunities/${opportunity.id}`);
      return response(opportunity);
    });

    const detail = await getOpportunityData(opportunity.id, fetcher);

    expect(detail.opportunity.items[0]?.publishedAt).toBe("2026-07-28T08:00:00.000Z");
    expect(detail.opportunity.coverageExplanation).toContain("No Arabic");
  });

  it("returns the safe public error for an unavailable gateway", async () => {
    await expect(getTodayData(async () => response({ message: "Database is unavailable" }, 503))).rejects.toMatchObject({
      kind: "unavailable",
      status: 503,
      message: "Database is unavailable",
    });
  });

  it("sends only a gateway mutation and parses the canonical disposition result", async () => {
    const state: OpportunityDispositionState = {
      opportunityID: bootstrapFixture.opportunities[0]!.id,
      disposition: "watched",
      changedAt: "2026-07-28T08:20:00.000Z",
      mutationID: "50000000-0000-4000-8000-000000000099",
      outcome: "applied",
    };
    const fetcher = vi.fn(async (path: string, init?: RequestInit) => {
      expect(path).toBe(`/opportunities/${state.opportunityID}/disposition`);
      expect(init?.method).toBe("PATCH");
      expect(new Headers(init?.headers).get("authorization")).toBeNull();
      expect(JSON.parse(String(init?.body))).toEqual({
        disposition: "watched",
        changedAt: state.changedAt,
        mutationID: state.mutationID,
      });
      return response(state);
    });

    const result = await updateOpportunityDisposition(state.opportunityID, "watched", fetcher, {
      changedAt: state.changedAt,
      mutationID: state.mutationID,
    });

    expect(result).toEqual(state);
  });
});
