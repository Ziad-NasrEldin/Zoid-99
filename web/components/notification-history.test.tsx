import React from "react";
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { NotificationHistory } from "@/components/notification-history";
import { BROWSER_NOTIFICATION_FEATURE_ENABLED } from "@/lib/notifications-client";

const immediateId = "40000000-0000-4000-8000-000000000001";
const digestId = "40000000-0000-4000-8000-000000000002";
const opportunityId = "10000000-0000-4000-8000-000000000001";

function notification(id: string, delivery: "Immediate" | "Digest", isRead: boolean) {
  return { id, opportunityID: opportunityId, title: delivery === "Immediate" ? "Immediate verified release" : "Digest research signal", delivery, createdAt: "2026-07-28T08:05:00.000Z", isRead };
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("NotificationHistory", () => {
  it("renders gateway history once in immediate and digest groups with exact opportunity links", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ items: [notification(immediateId, "Immediate", false), notification(digestId, "Digest", true), notification(digestId, "Digest", true)], nextCursor: null, serverTime: "2026-07-28T08:06:00.000Z" }), { status: 200, headers: { "content-type": "application/json" } })));

    render(<NotificationHistory />);

    expect(await screen.findByRole("heading", { name: "Immediate alerts" })).toBeVisible();
    expect(screen.getByRole("heading", { name: "Digest groups" })).toBeVisible();
    expect(screen.getAllByRole("link", { name: /verified release|research signal/ })).toHaveLength(2);
    expect(screen.getAllByRole("link")[0]).toHaveAttribute("href", `/opportunities/${opportunityId}`);
    expect(screen.getByText("Browser notifications: disabled")).toBeVisible();
  });

  it("uses an idempotency key and updates read state without duplicating the row", async () => {
    const fetcher = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ items: [notification(immediateId, "Immediate", false)], nextCursor: null, serverTime: "2026-07-28T08:06:00.000Z" }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify(notification(immediateId, "Immediate", true)), { status: 200 }));
    vi.stubGlobal("fetch", fetcher);

    render(<NotificationHistory />);
    await screen.findByRole("button", { name: "Mark read" });
    await screen.getByRole("button", { name: "Mark read" }).click();

    await waitFor(() => expect(screen.getByRole("button", { name: "Mark unread" })).toBeVisible());
    expect(fetcher).toHaveBeenCalledTimes(2);
    const mutation = fetcher.mock.calls[1];
    expect(mutation[0]).toBe(`/api/gateway/notifications/${immediateId}`);
    expect(mutation[1].method).toBe("PATCH");
    expect(mutation[1].headers["idempotency-key"]).toEqual(expect.any(String));
    expect(screen.getAllByRole("link", { name: /verified release/ })).toHaveLength(1);
  });

  it("keeps browser notification enrollment disabled", () => {
    expect(BROWSER_NOTIFICATION_FEATURE_ENABLED).toBe(false);
  });
});
