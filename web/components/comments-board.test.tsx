import React from "react";
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { CommentsBoard } from "@/components/comments-board";

const sourceId = "20000000-0000-4000-8000-000000000001";
const commentId = "60000000-0000-4000-8000-000000000001";

function sourceItem() {
  return {
    id: sourceId,
    group: "Comments",
    externalID: "comment-1",
    title: "What changed?",
    summary: "A source-backed audience question.",
    author: "Audience account",
    url: "https://comments.example/source/1",
    publishedAt: "2026-07-28T08:00:00.000Z",
    collectedAt: "2026-07-28T08:05:00.000Z",
    language: "en",
    country: "EG",
    topicKey: "official-release",
    isOriginalSource: false,
    credibility: 0.7,
    engagement: 4,
    verification: "Unverified",
  };
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("CommentsBoard", () => {
  it("renders only server-provided groups and keeps source truth attached", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({
      items: [{ id: commentId, question: "What changed?", count: 2, demand: "High", language: "en", sourceItems: [sourceItem()] }],
      nextCursor: null,
      serverTime: "2026-07-28T08:06:00.000Z",
      availability: { group: "Comments", state: "Connected", dataTruth: "Live", evidence: "Comments provider returned the projection.", repairAction: "No repair action required." },
    }), { status: 200 })));

    render(<CommentsBoard />);

    expect(await screen.findByRole("heading", { name: "Grouped signals" })).toBeVisible();
    expect(screen.getByRole("heading", { name: "What changed?" })).toBeVisible();
    expect(screen.getByText("Audience account")).toBeVisible();
    expect(screen.getByRole("link", { name: "Open original source" })).toHaveAttribute("href", "https://comments.example/source/1");
    expect(screen.getByText(/captured/)).toHaveTextContent("28 Jul 2026");
  });

  it("shows unavailable provider truth without fabricating comment groups", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({
      items: [], nextCursor: null, serverTime: "2026-07-28T08:06:00.000Z",
      availability: { group: "Comments", state: "Unavailable", dataTruth: "Missing", evidence: "No comments source is connected.", repairAction: "Connect a supported comments source." },
    }), { status: 200 })));

    render(<CommentsBoard />);

    expect(await screen.findByRole("heading", { name: "No comment data is available" })).toBeVisible();
    expect(screen.getByText("No comments source is connected.")).toBeVisible();
    expect(screen.getByText("Connect a supported comments source.")).toBeVisible();
    expect(screen.queryByRole("heading", { name: "Grouped signals" })).not.toBeInTheDocument();
  });
});
