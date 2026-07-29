"use client";

import { ArrowLeft, ArrowUpRight, ChevronRight, RefreshCw, Search } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";

import {
  defaultTopicFilters,
  fetchTopicDetail,
  fetchTopicsPage,
  parseTopicFilters,
  serializeTopicFilters,
  type RadarClientError,
  type TopicFilters,
} from "@/lib/radar-client";
import type { Opportunity, Topic, TopicDetail } from "@zoid99/contracts";

import styles from "./topics-page.module.css";

type ListState =
  | { query: string; status: "loading" }
  | { query: string; status: "ready"; items: Topic[]; nextCursor: string | null; serverTime: string }
  | { query: string; status: "unavailable"; message: string };

type DetailState =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "ready"; topic: TopicDetail }
  | { status: "unavailable"; message: string };

function formatDate(value: string): string {
  return new Intl.DateTimeFormat("en", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

function Evidence({ opportunity }: { opportunity: Opportunity }) {
  const source = opportunity.originalSource ?? opportunity.items[0];
  return (
    <div className={styles.evidence}>
      <div>
        <span className={styles.label}>Truth</span>
        <strong>{opportunity.verification}</strong>
      </div>
      <div>
        <span className={styles.label}>Earliest known source</span>
        {source ? (
          <>
            <span>{source.group} / {formatDate(source.publishedAt)}</span>
            <a href={source.url} target="_blank" rel="noreferrer">Open original source <ArrowUpRight aria-hidden="true" size={14} /></a>
          </>
        ) : <span className={styles.missing}>No source evidence attached</span>}
      </div>
    </div>
  );
}

function TopicDetailPanel({ detail, onBack }: { detail: TopicDetail; onBack: () => void }) {
  return (
    <section className={styles.detail} aria-labelledby="topic-detail-heading">
      <button type="button" className={styles.backButton} onClick={onBack}><ArrowLeft aria-hidden="true" size={16} /> Back to topic index</button>
      <div className={styles.detailHeader}>
        <p className={styles.eyebrow}>TOPIC EVIDENCE / SERVER COMPUTED</p>
        <h2 id="topic-detail-heading">{detail.title}</h2>
        <div className={styles.topicMeta}>
          <span>{detail.opportunityCount} opportunities</span>
          <span>{detail.freshness}</span>
          <span>Latest activity {formatDate(detail.latestActivityAt)}</span>
        </div>
      </div>
      <div className={styles.detailRows}>
        {detail.opportunities.length === 0 ? (
          <div className={styles.statePanel} role="status"><strong>No opportunity evidence for this topic</strong><span>The server returned a topic with no attached opportunities.</span></div>
        ) : detail.opportunities.map((opportunity) => (
          <article className={styles.detailRow} key={opportunity.id}>
            <h3>{opportunity.title}</h3>
            <p>{opportunity.brief}</p>
            <Evidence opportunity={opportunity} />
          </article>
        ))}
      </div>
    </section>
  );
}

export function TopicsPage() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const queryString = searchParams.toString();
  const filters = useMemo(() => parseTopicFilters(queryString), [queryString]);
  const [draftState, setDraftState] = useState<{ query: string; value: TopicFilters }>({ query: queryString, value: filters });
  const draft = draftState.query === queryString ? draftState.value : filters;
  const [listState, setListState] = useState<ListState>({ query: queryString, status: "loading" });
  const [detailState, setDetailState] = useState<{ topic: string; state: DetailState }>({ topic: "", state: { status: "idle" } });
  const visibleListState: ListState = listState.query === queryString ? listState : { query: queryString, status: "loading" };
  const visibleDetailState: DetailState = detailState.topic === filters.topic ? detailState.state : filters.topic ? { status: "loading" } : { status: "idle" };

  useEffect(() => {
    const controller = new AbortController();
    fetchTopicsPage(filters, controller.signal)
      .then((page) => setListState({ query: queryString, status: "ready", ...page }))
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        const message = (error as RadarClientError).message || "The private data gateway is unavailable.";
        setListState({ query: queryString, status: "unavailable", message });
      });
    return () => controller.abort();
  }, [filters, queryString]);

  useEffect(() => {
    if (!filters.topic) {
      return;
    }
    const controller = new AbortController();
    fetchTopicDetail(filters.topic, controller.signal)
      .then((topic) => setDetailState({ topic: filters.topic, state: { status: "ready", topic } }))
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        const message = (error as RadarClientError).message || "The topic evidence is unavailable.";
        setDetailState({ topic: filters.topic, state: { status: "unavailable", message } });
      });
    return () => controller.abort();
  }, [filters.topic]);

  const goTo = (next: TopicFilters) => {
    const query = serializeTopicFilters(next);
    setDraftState({ query, value: next });
    router.push(query ? `${pathname}?${query}` : pathname);
  };

  const submitSearch = () => goTo({ ...draft, cursor: "", topic: "" });
  const reset = () => {
    goTo(defaultTopicFilters);
  };

  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <div>
          <p className={styles.eyebrow}>03 / Interpret</p>
          <h1>Topics</h1>
          <p className={styles.description}>Server-computed topic groupings with freshness, truth mix, and original evidence kept attached.</p>
        </div>
        <div className={styles.headerState} role="status" aria-live="polite">
          <span className={styles.label}>STATE</span>
          <strong>{visibleListState.status === "ready" ? "LIVE QUERY" : visibleListState.status === "loading" ? "LOADING" : "UNAVAILABLE"}</strong>
        </div>
      </header>

      <form className={styles.searchBar} aria-label="Topic search" onSubmit={(event) => { event.preventDefault(); submitSearch(); }}>
        <label>
          <span className={styles.label}>Search topics</span>
          <span className={styles.searchInput}><Search aria-hidden="true" size={17} /><input aria-label="Search topics" value={draft.search} maxLength={200} placeholder="Search titles" onChange={(event) => setDraftState({ query: queryString, value: { ...draft, search: event.target.value, cursor: "" } })} /></span>
        </label>
        <button type="submit" className={styles.primaryButton}><Search aria-hidden="true" size={16} /> Search</button>
        <button type="button" className={styles.secondaryButton} onClick={reset}>Reset</button>
        <span className={styles.queryLimit}>Up to 25 topics per page</span>
      </form>

      {filters.topic && visibleDetailState.status === "ready" ? <TopicDetailPanel detail={visibleDetailState.topic} onBack={() => router.back()} /> : null}
      {filters.topic && visibleDetailState.status === "loading" ? <div className={styles.statePanel} role="status"><RefreshCw aria-hidden="true" size={18} /> Loading server-computed evidence</div> : null}
      {filters.topic && visibleDetailState.status === "unavailable" ? <div className={`${styles.statePanel} ${styles.unavailable}`} role="status"><strong>Topic evidence is unavailable</strong><span>{visibleDetailState.message}</span><span>No evidence has been fabricated.</span></div> : null}

      <section className={styles.index} aria-labelledby="topic-index-heading">
        <div className={styles.indexHeader}>
          <div><p className={styles.eyebrow}>TOPIC INDEX</p><h2 id="topic-index-heading">Research clusters</h2></div>
          <div className={styles.indexSummary}>{visibleListState.status === "ready" ? `${visibleListState.items.length} loaded` : "Records pending"}</div>
        </div>
        {visibleListState.status === "loading" ? <div className={styles.statePanel} role="status"><RefreshCw aria-hidden="true" size={18} /> Loading topic index</div> : null}
        {visibleListState.status === "unavailable" ? <div className={`${styles.statePanel} ${styles.unavailable}`} role="status"><strong>Topic index is unavailable</strong><span>{visibleListState.message}</span><span>Nothing has been fabricated for this view.</span></div> : null}
        {visibleListState.status === "ready" && visibleListState.items.length === 0 ? <div className={styles.statePanel} role="status"><strong>No topics matched this search</strong><span>Broaden the search to inspect the server-computed topic index.</span></div> : null}
        {visibleListState.status === "ready" && visibleListState.items.length > 0 ? (
          <div className={styles.topicRows}>
            {visibleListState.items.map((topic) => (
              <button type="button" className={styles.topicRow} key={topic.topicKey} onClick={() => goTo({ ...filters, topic: topic.topicKey })}>
                <span className={styles.topicName} title={topic.title}>{topic.title}</span>
                <span>{topic.opportunityCount} opportunities</span>
                <span>{topic.freshness}</span>
                <span>{topic.verificationMix.confirmed} confirmed / {topic.verificationMix.unverified} unverified</span>
                <ChevronRight aria-hidden="true" size={18} />
              </button>
            ))}
          </div>
        ) : null}
        {visibleListState.status === "ready" ? <div className={styles.pagination}><span>Server time {formatDate(visibleListState.serverTime)}</span><button type="button" className={styles.secondaryButton} disabled={!visibleListState.nextCursor} onClick={() => goTo({ ...filters, cursor: visibleListState.nextCursor ?? "" })}>Next page <ChevronRight aria-hidden="true" size={16} /></button></div> : null}
      </section>
    </div>
  );
}
