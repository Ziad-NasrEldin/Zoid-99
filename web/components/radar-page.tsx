"use client";

import { ArrowUpRight, ChevronRight, RefreshCw } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";

import { RadarFilters } from "@/components/radar-filters";
import {
  defaultRadarFilters,
  fetchRadarPage,
  parseRadarFilters,
  serializeRadarFilters,
  type RadarFilters as RadarFilterState,
  type RadarClientError,
} from "@/lib/radar-client";
import type { Opportunity } from "@zoid99/contracts";
import { isBlockedSourceURL, readSourceBlocklist } from "@/lib/source-blocklist";

import styles from "./radar-page.module.css";

type LoadState =
  | { query: string; status: "loading" }
  | { query: string; status: "ready"; items: Opportunity[]; nextCursor: string | null; serverTime: string }
  | { query: string; status: "unavailable"; message: string };

function formatDate(value: string): string {
  return new Intl.DateTimeFormat("en", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

function stateLabel(value: string): string {
  return value.replace(/([a-z])([A-Z])/g, "$1 $2").replace(/^./, (letter) => letter.toUpperCase());
}

function sourceLabel(opportunity: Opportunity): string {
  return opportunity.originalSource?.group ?? opportunity.items[0]?.group ?? "Source unavailable";
}

function ResearchRow({ opportunity }: { opportunity: Opportunity }) {
  const evidence = opportunity.originalSource ?? opportunity.items[0];
  return (
    <article className={styles.ledgerRow}>
      <div className={styles.rowMain}>
        <div className={styles.rowTitleLine}>
          <h3>{opportunity.title}</h3>
          <span className={styles.truthTag}>{opportunity.verification}</span>
        </div>
        <p className={styles.rowBrief}>{opportunity.brief}</p>
        <div className={styles.rowMeta}>
          <span>{sourceLabel(opportunity)}</span>
          <span>{opportunity.topicKey}</span>
          <span>{stateLabel(opportunity.disposition)}</span>
          {opportunity.isHighPriority ? <span className={styles.priorityTag}>High priority</span> : null}
        </div>
      </div>
      <div className={styles.rowEvidence}>
        <span className={styles.metaLabel}>Earliest evidence</span>
        {evidence ? (
          <>
            <span>{formatDate(evidence.publishedAt)}</span>
            <a href={evidence.url} target="_blank" rel="noreferrer">Open source <ArrowUpRight aria-hidden="true" size={14} /></a>
          </>
        ) : <span className={styles.missing}>No source evidence attached</span>}
      </div>
      <a className={styles.rowLink} href={`/topics?topic=${encodeURIComponent(opportunity.topicKey)}`} aria-label={`Open topic ${opportunity.topicKey}`}>
        <ChevronRight aria-hidden="true" size={18} />
      </a>
    </article>
  );
}

export function RadarPage() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const queryString = searchParams.toString();
  const filters = useMemo(() => parseRadarFilters(queryString), [queryString]);
  const [draftState, setDraftState] = useState<{ query: string; value: RadarFilterState }>({ query: queryString, value: filters });
  const draft = draftState.query === queryString ? draftState.value : filters;
  const [loadState, setLoadState] = useState<LoadState>({ query: queryString, status: "loading" });
  const visibleState: LoadState = loadState.query === queryString ? loadState : { query: queryString, status: "loading" };

  useEffect(() => {
    const controller = new AbortController();
    fetchRadarPage(filters, controller.signal)
      .then((page) => {
        const domains = readSourceBlocklist();
        const items = domains.length === 0
          ? page.items
          : page.items.filter((opportunity) => !opportunity.items.some((item) => isBlockedSourceURL(item.url, domains)));
        setLoadState({ query: queryString, status: "ready", ...page, items });
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        const message = (error as RadarClientError).message || "The private data gateway is unavailable.";
        setLoadState({ query: queryString, status: "unavailable", message });
      });
    return () => controller.abort();
  }, [filters, queryString]);

  const goTo = (next: RadarFilterState) => {
    const query = serializeRadarFilters(next);
    setDraftState({ query, value: next });
    router.push(query ? `${pathname}?${query}` : pathname);
  };

  const reset = () => {
    goTo(defaultRadarFilters);
  };

  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <div>
          <p className={styles.eyebrow}>02 / Detect</p>
          <h1>Live Radar</h1>
          <p className={styles.description}>A chronological view of real research signals, with source truth attached to every item.</p>
        </div>
        <div className={styles.headerState} role="status" aria-live="polite">
          <span className={styles.metaLabel}>STATE</span>
          <strong>{visibleState.status === "ready" ? "LIVE QUERY" : visibleState.status === "loading" ? "LOADING" : "UNAVAILABLE"}</strong>
        </div>
      </header>

      <RadarFilters value={draft} onChange={(value) => setDraftState({ query: queryString, value })} onSubmit={() => goTo(draft)} onReset={reset} />

      <section className={styles.ledger} aria-labelledby="radar-ledger-heading">
        <div className={styles.ledgerHeader}>
          <div>
            <p className={styles.eyebrow}>RESEARCH LEDGER</p>
            <h2 id="radar-ledger-heading">Signals worth checking</h2>
          </div>
          <div className={styles.ledgerSummary}>
            <span>{visibleState.status === "ready" ? `${visibleState.items.length} loaded` : "Records pending"}</span>
            <span>Limit {25}</span>
          </div>
        </div>

        {visibleState.status === "loading" ? <div className={styles.statePanel} role="status"><RefreshCw aria-hidden="true" size={18} /> Loading gateway results</div> : null}
        {visibleState.status === "unavailable" ? (
          <div className={`${styles.statePanel} ${styles.unavailable}`} role="status">
            <strong>Radar data is unavailable</strong>
            <span>{visibleState.message}</span>
            <span>Nothing has been fabricated for this view.</span>
          </div>
        ) : null}
        {visibleState.status === "ready" && visibleState.items.length === 0 ? (
          <div className={styles.statePanel} role="status">
            <strong>No research matched these filters</strong>
            <span>Try a broader source, freshness, verification, or disposition filter.</span>
          </div>
        ) : null}
        {visibleState.status === "ready" && visibleState.items.length > 0 ? (
          <div className={styles.ledgerRows}>
            {visibleState.items.map((opportunity) => <ResearchRow key={opportunity.id} opportunity={opportunity} />)}
          </div>
        ) : null}
        {visibleState.status === "ready" ? (
          <div className={styles.pagination}>
            <span>Server time {formatDate(visibleState.serverTime)}</span>
            <button type="button" className={styles.secondaryButton} disabled={!visibleState.nextCursor} onClick={() => goTo({ ...filters, cursor: visibleState.nextCursor ?? "" })}>
              Next page <ChevronRight aria-hidden="true" size={16} />
            </button>
          </div>
        ) : null}
      </section>
    </div>
  );
}
