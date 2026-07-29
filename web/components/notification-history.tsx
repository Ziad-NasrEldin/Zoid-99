"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";

import {
  BROWSER_NOTIFICATION_FEATURE_ENABLED,
  getNotificationHistory,
  NotificationsClientError,
  setNotificationReadState,
  type NotificationRecord,
} from "@/lib/notifications-client";
import styles from "./notification-history.module.css";

const dateFormatter = new Intl.DateTimeFormat("en-GB", {
  day: "2-digit",
  month: "short",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
  timeZoneName: "short",
});

function formatDate(value: string): string {
  return dateFormatter.format(new Date(value));
}

function uniqueNotifications(items: NotificationRecord[]): NotificationRecord[] {
  const byId = new Map<string, NotificationRecord>();
  for (const item of items) byId.set(item.id, item);
  return [...byId.values()].sort((left, right) => right.createdAt.localeCompare(left.createdAt));
}

export function NotificationHistory() {
  const [items, setItems] = useState<NotificationRecord[]>([]);
  const [status, setStatus] = useState<"loading" | "ready" | "unavailable" | "error">("loading");
  const [message, setMessage] = useState<string | null>(null);
  const [pendingIds, setPendingIds] = useState<Set<string>>(new Set());

  const load = useCallback(async () => {
    setStatus("loading");
    setMessage(null);
    try {
      const page = await getNotificationHistory();
      setItems(uniqueNotifications(page.items));
      setStatus("ready");
    } catch (error) {
      setStatus(error instanceof NotificationsClientError && error.kind === "unavailable" ? "unavailable" : "error");
      setMessage(error instanceof Error ? error.message : "The notification history could not be loaded.");
    }
  }, []);

  useEffect(() => {
    const request = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(request);
  }, [load]);

  const groups = useMemo(
    () => [
      { delivery: "Immediate" as const, label: "Immediate alerts", items: items.filter((item) => item.delivery === "Immediate") },
      { delivery: "Digest" as const, label: "Digest groups", items: items.filter((item) => item.delivery === "Digest") },
    ],
    [items],
  );

  async function changeReadState(item: NotificationRecord) {
    if (pendingIds.has(item.id)) return;
    const nextState = !item.isRead;
    const previousItems = items;
    const idempotencyKey = crypto.randomUUID();
    setPendingIds((current) => new Set(current).add(item.id));
    setItems((current) => current.map((candidate) => candidate.id === item.id ? { ...candidate, isRead: nextState } : candidate));
    setMessage(null);

    try {
      const updated = await setNotificationReadState(item.id, nextState, undefined, idempotencyKey);
      setItems((current) => current.map((candidate) => candidate.id === updated.id ? updated : candidate));
    } catch (error) {
      setItems(previousItems);
      setMessage(error instanceof Error ? error.message : "The read state could not be saved.");
    } finally {
      setPendingIds((current) => {
        const next = new Set(current);
        next.delete(item.id);
        return next;
      });
    }
  }

  const totalUnread = items.filter((item) => !item.isRead).length;

  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <div>
          <p className={styles.eyebrow}>06 / Attend</p>
          <h1>Notifications</h1>
          <p className={styles.description}>Gateway-backed delivery history, grouped by urgency and linked to the exact opportunity that caused each alert.</p>
        </div>
        <p className={styles.headerState}><strong>{status === "ready" ? "STATE / LIVE GATEWAY" : `STATE / ${status.toUpperCase()}`}</strong><span>{totalUnread} unread</span></p>
      </header>

      <div className={styles.statusBar} role="status" aria-live="polite">
        <span>{status === "ready" ? `${items.length} recorded notification${items.length === 1 ? "" : "s"}` : "Reading notification history"}</span>
        <span className={styles.browserStatus}><strong>Browser notifications: disabled</strong>{BROWSER_NOTIFICATION_FEATURE_ENABLED ? "" : " - history and in-app actions only"}</span>
      </div>

      {status === "loading" ? <div className={styles.empty} role="status"><h2>Loading notification history</h2><p>The private gateway is being queried.</p></div> : null}
      {status !== "loading" && status !== "ready" ? (
        <div className={styles.error} role="alert">
          <h2>{status === "unavailable" ? "Notification history is unavailable" : "Notification history could not be read"}</h2>
          <p>{message ?? "The gateway did not return a usable history projection."}</p>
          <button className={styles.retryButton} type="button" onClick={() => void load()}>Try again</button>
        </div>
      ) : null}
      {status === "ready" && items.length === 0 ? (
        <div className={styles.empty} role="status"><h2>No notification history yet</h2><p>The gateway returned no recorded alerts or digests. No placeholder notifications are shown.</p></div>
      ) : null}
      {status === "ready" && items.length > 0 ? (
        <div className={styles.ledger}>
          {groups.map((group) => (
            <section className={styles.group} key={group.delivery} aria-labelledby={`notification-group-${group.delivery.toLowerCase()}`}>
              <header className={styles.groupHeader}>
                <h2 id={`notification-group-${group.delivery.toLowerCase()}`}>{group.label}</h2>
                <p className={styles.count}>{group.items.length} record{group.items.length === 1 ? "" : "s"}</p>
              </header>
              {group.items.length > 0 ? (
                <div className={styles.rows}>
                  {group.items.map((item) => (
                    <article className={`${styles.notificationRow} ${item.isRead ? "" : styles.unread}`} key={item.id}>
                      <div className={styles.notificationMeta}><span>Received</span><strong>{formatDate(item.createdAt)}</strong></div>
                      <div className={styles.notificationMeta}><span>Reason</span><strong>{item.delivery} notification</strong></div>
                      <div className={styles.notificationMeta}><span>Opportunity</span><Link className={styles.opportunityLink} href={`/opportunities/${item.opportunityID}`}>{item.title}</Link></div>
                      <div className={styles.notificationMeta}><span>Read state</span><strong className={styles.state}>{item.isRead ? "Read" : "Unread"}</strong></div>
                      <button className={styles.readButton} type="button" disabled={pendingIds.has(item.id)} aria-pressed={item.isRead} onClick={() => void changeReadState(item)}>{item.isRead ? "Mark unread" : "Mark read"}</button>
                    </article>
                  ))}
                </div>
              ) : <p className={styles.empty}>No {group.delivery.toLowerCase()} notifications in this history.</p>}
            </section>
          ))}
        </div>
      ) : null}
      {message && status === "ready" ? <p role="alert">{message}</p> : null}
    </div>
  );
}
