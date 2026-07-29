"use client";

import Link from "next/link";
import { Bookmark, ExternalLink, Eye, LoaderCircle, VolumeX, X } from "lucide-react";
import { useCallback, useEffect, useState } from "react";

import {
  formatResearchDate,
  getTodayData,
  isArabicText,
  ResearchClientError,
  updateOpportunityDisposition,
  type GatewayFetcher,
  type TodayData,
} from "@/lib/research-client";
import type { Opportunity, OpportunityDisposition, OpportunityDispositionState } from "@zoid99/contracts";
import styles from "./today.module.css";

type TodayResearchProps = {
  loadToday?: (fetcher?: GatewayFetcher) => Promise<TodayData>;
  mutateDisposition?: (id: string, disposition: OpportunityDisposition) => Promise<OpportunityDispositionState>;
};

const dispositionLabels: Record<OpportunityDisposition, string> = {
  active: "Active",
  saved: "Save",
  watched: "Watch",
  dismissed: "Dismiss",
  muted: "Mute",
};

const actionIcons: Record<Exclude<OpportunityDisposition, "active">, typeof Bookmark> = {
  saved: Bookmark,
  watched: Eye,
  dismissed: X,
  muted: VolumeX,
};

function totalScore(opportunity: Opportunity): number {
  return Object.values(opportunity.score).reduce((sum, value) => sum + value, 0);
}

function sortToday(opportunities: Opportunity[]): Opportunity[] {
  return opportunities
    .filter((opportunity) => !["dismissed", "muted"].includes(opportunity.disposition))
    .sort((left, right) => {
      if (left.isHighPriority !== right.isHighPriority) return left.isHighPriority ? -1 : 1;
      return totalScore(right) - totalScore(left);
    });
}

function truthClass(dataTruth: TodayData["dataTruth"]): string {
  return {
    Live: styles.truthLive,
    Cached: styles.truthCached,
    Missing: styles.truthMissing,
    Unavailable: styles.truthUnavailable,
  }[dataTruth];
}

function truthLabel(dataTruth: TodayData["dataTruth"]): string {
  return {
    Live: "Live data",
    Cached: "Cached data",
    Missing: "Data missing",
    Unavailable: "Data unavailable",
  }[dataTruth];
}

function StatePanel({
  eyebrow,
  title,
  body,
  action,
}: {
  eyebrow: string;
  title: string;
  body: string;
  action?: React.ReactNode;
}) {
  return (
    <div className={styles.statePanel} role="status">
      <span className={styles.statusLabel}>{eyebrow}</span>
      <h2>{title}</h2>
      <p>{body}</p>
      {action}
    </div>
  );
}

export function TodayResearch({ loadToday = getTodayData, mutateDisposition = updateOpportunityDisposition }: TodayResearchProps) {
  const [state, setState] = useState<{ status: "loading" | "ready" | "error" | "unavailable"; data?: TodayData; message?: string }>({ status: "loading" });
  const [pendingID, setPendingID] = useState<string | null>(null);
  const [mutationError, setMutationError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setState((current) => ({ ...current, status: "loading", message: undefined }));
    try {
      setState({ status: "ready", data: await loadToday() });
    } catch (error) {
      const researchError = error instanceof ResearchClientError ? error : null;
      setState({
        status: researchError?.kind === "unavailable" ? "unavailable" : "error",
        message: researchError?.message ?? "Today research could not be loaded.",
      });
    }
  }, [loadToday]);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  async function changeDisposition(opportunityID: string, disposition: OpportunityDisposition) {
    if (!state.data || pendingID) return;
    const previous = state.data;
    const nextData: TodayData = {
      ...previous,
      opportunities: previous.opportunities.map((opportunity) =>
        opportunity.id === opportunityID
          ? { ...opportunity, disposition, dispositionUpdatedAt: new Date().toISOString() }
          : opportunity,
      ),
    };
    setMutationError(null);
    setPendingID(opportunityID);
    setState({ status: "ready", data: nextData });
    try {
      const canonical = await mutateDisposition(opportunityID, disposition);
      setState({
        status: "ready",
        data: {
          ...nextData,
          opportunities: nextData.opportunities.map((opportunity) =>
            opportunity.id === opportunityID
              ? {
                  ...opportunity,
                  disposition: canonical.disposition,
                  dispositionUpdatedAt: canonical.changedAt,
                }
              : opportunity,
          ),
        },
      });
    } catch {
      setState({ status: "ready", data: previous });
      setMutationError("That change could not be saved. The previous state has been restored.");
    } finally {
      setPendingID(null);
    }
  }

  const data = state.data;
  const opportunities = data ? sortToday([...data.opportunities]) : [];

  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <div>
          <p className={styles.eyebrow}>01 / Review</p>
          <h1 className={styles.title}>Today</h1>
          <p className={styles.description}>
            Active research opportunities with their original evidence still attached.
          </p>
        </div>
        <p className={styles.state}>{data ? `${opportunities.length} active ${opportunities.length === 1 ? "item" : "items"}` : "STATE / LOADING"}</p>
      </header>

      {state.status === "ready" && data ? (
        <>
          <div className={styles.syncLine} aria-label="Today data status">
            <span className={truthClass(data.dataTruth)}>{truthLabel(data.dataTruth)}</span>
            <span>Last successful sync: {formatResearchDate(data.lastSuccessfulSync)}</span>
            <span>Immediate alerts and digest delivery are shown per opportunity.</span>
          </div>
          <section className={styles.ledger} aria-labelledby="today-ledger-heading">
            <div className={styles.ledgerHeading}>
              <h2 id="today-ledger-heading">Priority ledger</h2>
              <span className={styles.count}>{opportunities.length} visible</span>
            </div>
            <div className={styles.columns} aria-hidden="true">
              <span className={styles.columnLabel}>Priority</span>
              <span className={styles.columnLabel}>Opportunity</span>
              <span className={styles.columnLabel}>Original evidence</span>
              <span className={styles.columnLabel}>Delivery and actions</span>
            </div>
            {opportunities.length === 0 ? (
              <StatePanel
                eyebrow={data.dataTruth === "Missing" ? "DATA STATE / MISSING" : "TODAY / CLEAR"}
                title="No active opportunities today"
                body={data.opportunities.length === 0 ? "The gateway returned no research records. This is an empty result, not a fabricated zero." : "No active items need attention right now."}
              />
            ) : (
              opportunities.map((opportunity) => (
                <TodayRow
                  key={opportunity.id}
                  opportunity={opportunity}
                  notificationDelivery={data.notifications.find((notification) => notification.opportunityID === opportunity.id)?.delivery}
                  pending={pendingID === opportunity.id}
                  onDisposition={changeDisposition}
                  mutationError={mutationError}
                />
              ))
            )}
          </section>
        </>
      ) : state.status === "loading" ? (
        <section className={styles.ledger} aria-busy="true" aria-label="Loading Today research">
          <StatePanel eyebrow="DATA STATE / LOADING" title="Reading the research ledger" body="The authenticated gateway is checking the latest server-backed evidence." />
        </section>
      ) : (
        <section className={styles.ledger} aria-label="Today research unavailable">
          <StatePanel
            eyebrow={state.status === "unavailable" ? "DATA STATE / UNAVAILABLE" : "DATA STATE / ERROR"}
            title={state.status === "unavailable" ? "The research gateway is unavailable" : "Today could not be loaded"}
            body={state.message ?? "The response did not arrive. Try again when the private gateway is reachable."}
            action={<button className={styles.retry} type="button" onClick={() => void load()}>Try again</button>}
          />
        </section>
      )}
    </div>
  );
}

function TodayRow({
  opportunity,
  notificationDelivery,
  pending,
  onDisposition,
  mutationError,
}: {
  opportunity: Opportunity;
  notificationDelivery?: "Immediate" | "Digest";
  pending: boolean;
  onDisposition: (id: string, disposition: OpportunityDisposition) => Promise<void>;
  mutationError: string | null;
}) {
  const originalSource = opportunity.originalSource;
  return (
    <article className={styles.row}>
      <div
        className={styles.priority}
        aria-label={opportunity.isHighPriority ? "High priority" : "Standard priority"}
      >
        {opportunity.isHighPriority ? "High" : "Standard"}
      </div>
      <div className={styles.rowMain}>
        <Link className={styles.opportunityLink} href={`/opportunities/${opportunity.id}`} dir={isArabicText(opportunity.title) ? "rtl" : "auto"}>
          {opportunity.title}
        </Link>
        <p className={styles.brief} dir={isArabicText(opportunity.brief) ? "rtl" : "auto"}>{opportunity.brief}</p>
        <Link className={styles.readMore} href={`/opportunities/${opportunity.id}`} aria-label={`Read more about ${opportunity.title}`}>
          Read more <span aria-hidden="true">→</span>
        </Link>
        <div className={styles.actions} aria-label={`Actions for ${opportunity.title}`}>
          {(Object.keys(actionIcons) as Array<Exclude<OpportunityDisposition, "active">>).map((disposition) => {
            const Icon = actionIcons[disposition];
            return (
              <button
                key={disposition}
                className={`${styles.action} ${opportunity.disposition === disposition ? styles.actionSelected : ""}`}
                type="button"
                disabled={pending}
                aria-pressed={opportunity.disposition === disposition}
                onClick={() => void onDisposition(opportunity.id, disposition)}
              >
                {pending && opportunity.disposition !== disposition ? <LoaderCircle aria-hidden="true" size={14} className="spin" /> : <Icon aria-hidden="true" size={14} strokeWidth={1.6} />}
                {dispositionLabels[disposition]}
              </button>
            );
          })}
        </div>
        {mutationError ? <p className={styles.mutationError} role="alert">{mutationError}</p> : null}
      </div>
      <div className={styles.metaStack}>
        <span>Published: {formatResearchDate(originalSource?.publishedAt ?? opportunity.earliestPublishedAt)}</span>
        <span>Collected: {formatResearchDate(originalSource?.collectedAt ?? null)}</span>
        <span>{originalSource?.group ?? "Original source unavailable"}</span>
        {originalSource ? (
          <>
            <span className={styles.sourceURL} title={originalSource.url}>URL: {originalSource.url}</span>
            <a className={styles.sourceLink} href={originalSource.url} target="_blank" rel="noreferrer">Open original <ExternalLink aria-hidden="true" size={13} strokeWidth={1.6} /></a>
          </>
        ) : null}
      </div>
      <div className={styles.metaStack}>
        <span className={styles.delivery}>{notificationDelivery ? `${notificationDelivery} delivery` : "No notification scheduled"}</span>
        <span>Verification: {opportunity.verification}</span>
        <span>Score: {totalScore(opportunity)}</span>
      </div>
    </article>
  );
}
