"use client";

import { useCallback, useEffect, useState } from "react";
import { z } from "zod";

import { commentsResponseSchema } from "@zoid99/contracts";
import styles from "./comments-board.module.css";

type CommentsResponse = z.infer<typeof commentsResponseSchema>;

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

function isArabic(value: string): boolean {
  return /[\u0600-\u06ff]/u.test(value);
}

export function CommentsBoard() {
  const [payload, setPayload] = useState<CommentsResponse | null>(null);
  const [status, setStatus] = useState<"loading" | "ready" | "unavailable" | "error">("loading");
  const [message, setMessage] = useState<string | null>(null);

  const load = useCallback(async () => {
    setStatus("loading");
    setMessage(null);
    try {
      const response = await fetch("/api/gateway/comments?limit=100", { headers: { accept: "application/json" } });
      const body = (await response.json().catch(() => null)) as { msg?: string; message?: string } | null;
      if (!response.ok) throw new Error(body?.msg ?? body?.message ?? "The comments gateway returned an error.");
      setPayload(commentsResponseSchema.parse(body));
      setStatus("ready");
    } catch (error) {
      setStatus(error instanceof Error && /gateway|unavailable/i.test(error.message) ? "unavailable" : "error");
      setMessage(error instanceof Error ? error.message : "The comments projection could not be loaded.");
    }
  }, []);

  useEffect(() => {
    const request = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(request);
  }, [load]);

  const availability = payload?.availability;
  const hasCommentData = status === "ready" && payload !== null && payload.items.length > 0;
  const dataUnavailable = availability && availability.dataTruth !== "Live";

  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <div>
          <p className={styles.eyebrow}>04 / Listen</p>
          <h1>Comments</h1>
          <p className={styles.description}>Server-grouped audience questions and confusion signals, shown only when the connected provider can support them.</p>
        </div>
        <p className={styles.headerState}><strong>{status === "ready" ? "STATE / GATEWAY PROJECTION" : `STATE / ${status.toUpperCase()}`}</strong><span>{hasCommentData ? `${payload.items.length} groups` : "No fabricated groups"}</span></p>
      </header>

      {status === "loading" ? <div className={styles.empty} role="status"><h2>Loading comments availability</h2><p>The private gateway is being queried. No comment data is assumed while it responds.</p></div> : null}
      {status !== "loading" && status !== "ready" ? (
        <div className={styles.error} role="alert">
          <h2>{status === "unavailable" ? "Comments are unavailable" : "Comments could not be read"}</h2>
          <p>{message ?? "The gateway did not return a usable comments projection."}</p>
          <button className={styles.retryButton} type="button" onClick={() => void load()}>Try again</button>
        </div>
      ) : null}

      {status === "ready" && availability ? (
        <section className={`${styles.availability} ${dataUnavailable ? styles.unavailable : ""}`} aria-labelledby="comments-availability-heading">
          <header className={styles.availabilityHeader}>
            <h2 id="comments-availability-heading">Provider availability</h2>
            <div className={styles.availabilityMeta}><span className={styles.truth}>{availability.dataTruth}</span><strong>{availability.state}</strong></div>
          </header>
          <div className={styles.availabilityBody}>
            <p><strong>Evidence:</strong> {availability.evidence}</p>
            <p><strong>Repair action:</strong> {availability.repairAction}</p>
          </div>
        </section>
      ) : null}

      {status === "ready" && !hasCommentData ? (
        <div className={`${styles.empty} ${dataUnavailable ? styles.missing : ""}`} role="status"><h2>{dataUnavailable ? "No comment data is available" : "No grouped comment signals yet"}</h2><p>{dataUnavailable ? "The gateway says this provider data is not available. This page does not infer or fabricate audience questions." : "The connected provider returned no grouped questions. No placeholder questions are shown."}</p></div>
      ) : null}

      {hasCommentData ? (
        <section className={styles.comments} aria-labelledby="comments-groups-heading">
          <header className={styles.commentsHeader}><h2 id="comments-groups-heading">Grouped signals</h2><p className={styles.commentCount}>{payload.items.length} server group{payload.items.length === 1 ? "" : "s"}</p></header>
          <div className={styles.commentRows}>
            {payload.items.map((comment) => (
              <article className={styles.comment} key={comment.id}>
                <header className={styles.commentHeader}>
                  <h3 dir={isArabic(comment.question) ? "rtl" : "auto"}>{comment.question}</h3>
                  <p className={styles.commentMeta}><span>{comment.count} signal{comment.count === 1 ? "" : "s"}</span><span>{comment.demand}</span><span>{comment.language}</span></p>
                </header>
                <div className={styles.commentBody}>
                  {comment.sourceItems.map((source) => (
                    <div className={styles.sourceRow} key={source.id}>
                      <div className={styles.sourceMeta}>
                        <strong>{source.author || "Source account unavailable"}</strong>
                        <span>{source.group} / captured {formatDate(source.collectedAt)} / published {formatDate(source.publishedAt)}</span>
                      </div>
                      <a className={styles.sourceLink} href={source.url} target="_blank" rel="noreferrer">Open original source</a>
                    </div>
                  ))}
                </div>
              </article>
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
