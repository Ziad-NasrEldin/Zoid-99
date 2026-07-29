import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { WatchlistPage } from "@/components/watchlist-page";
import type { WatchlistClient } from "@/lib/watchlist-client";

const existingEntry = {
  id: "00000000-0000-4000-8000-000000000001",
  kind: "Creator" as const,
  value: "UC1234567890",
  highPriority: false,
};

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((promiseResolve, promiseReject) => {
    resolve = promiseResolve;
    reject = promiseReject;
  });
  return { promise, resolve, reject };
}

function clientWith(entries = [existingEntry]): WatchlistClient {
  return {
    list: vi.fn().mockResolvedValue(entries),
    add: vi.fn(),
    edit: vi.fn(),
    replace: vi.fn(),
    remove: vi.fn(),
    validateKind: vi.fn(),
  } as unknown as WatchlistClient;
}

describe("WatchlistPage", () => {
  afterEach(() => cleanup());

  it("renders gateway entries, all seven kinds, and provider capability truth", async () => {
    render(<WatchlistPage client={clientWith()} />);

    expect(await screen.findByText("UC1234567890")).toBeVisible();
    expect(screen.getByRole("option", { name: "Creator" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Official source" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Company" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Keyword" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Topic" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Country" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Language" })).toBeInTheDocument();
    expect(screen.getByText("No watchlist connector is currently wired to Google Trends.")).toBeVisible();
  });

  it("blocks a duplicate before making a gateway mutation", async () => {
    const user = userEvent.setup();
    const client = clientWith();
    render(<WatchlistPage client={client} />);
    await screen.findByText("UC1234567890");

    const value = screen.getByLabelText("Value");
    await user.type(value, "UC1234567890");
    await user.click(screen.getByRole("button", { name: "Add entry" }));

    expect(screen.getByRole("alert")).toHaveTextContent("already on this watchlist");
    expect(client.add).not.toHaveBeenCalled();
  });

  it("shows an optimistic add and restores the previous list when the gateway rejects it", async () => {
    const user = userEvent.setup();
    const client = clientWith();
    const pending = deferred<typeof existingEntry>();
    vi.mocked(client.add).mockReturnValue(pending.promise);
    render(<WatchlistPage client={client} />);
    await screen.findByText("UC1234567890");

    await user.type(screen.getByLabelText("Value"), "new-keyword");
    await user.click(screen.getByRole("button", { name: "Add entry" }));
    expect(screen.getByText("new-keyword")).toBeVisible();

    pending.reject(new Error("gateway rejected"));
    await waitFor(() => expect(screen.queryByText("new-keyword")).not.toBeInTheDocument());
    expect(screen.getByRole("alert")).toHaveTextContent("could not be saved");
    expect(screen.getByText("UC1234567890")).toBeVisible();
  });

  it("optimistically toggles priority and rolls back on a failed patch", async () => {
    const user = userEvent.setup();
    const client = clientWith();
    const pending = deferred<typeof existingEntry>();
    vi.mocked(client.edit).mockReturnValue(pending.promise);
    render(<WatchlistPage client={client} />);
    await screen.findByText("UC1234567890");

    const priorityButton = screen.getByRole("button", { name: "Set high priority for UC1234567890" });
    await user.click(priorityButton);
    expect(priorityButton).toHaveAttribute("aria-pressed", "true");

    pending.reject(new Error("gateway rejected"));
    await waitFor(() => expect(priorityButton).toHaveAttribute("aria-pressed", "false"));
    expect(screen.getByRole("alert")).toHaveTextContent("could not be saved");
  });
});
