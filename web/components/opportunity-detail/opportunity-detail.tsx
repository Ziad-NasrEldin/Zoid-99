"use client";

import Link from "next/link";
import { ArrowLeft, Bookmark, ExternalLink, Eye, LoaderCircle, VolumeX, X } from "lucide-react";
import { useCallback, useEffect, useState } from "react";

import {
  formatResearchDate,
  getOpportunityData,
  isArabicText,
  ResearchClientError,
  updateOpportunityDisposition,
  type GatewayFetcher,
  type OpportunityData,
} from "@/lib/research-client";
import type { Opportunity, OpportunityDisposition } from "@zoid99/contracts";
import styles from "./opportunity-detail.module.css";

type OpportunityDetailProps = {
  id: string;
  loadOpportunity?: (id: string, fetcher?: GatewayFetcher) => Promise<OpportunityData>;
  mutateDisposition?: (id: string, disposition: OpportunityDisposition) => Promise<unknown>;
};

const actionLabels: Record<OpportunityDisposition, string> = {
  active: "Active",
  saved: "Save",
  watched: "Watch",
  dismissed: "Dismiss",
  muted: "Mute",
};

const actionIcons: Record<OpportunityDisposition, typeof Bookmark> = {
  active: Bookmark,
  saved: Bookmark,
  watched: Eye,
  dismissed: X,
  muted: VolumeX,
};

const scoreLabels: Array<[keyof Opportunity["score"], string]> = [
  ["freshness", "Freshness"],
  ["credibility", "Source credibility"],
  ["momentum", "Cross-source momentum"],
  ["creatorActivity", "Creator activity"],
  ["arabicCoverageGap", "Arabic coverage gap"],
  ["regionalRelevance", "Regional relevance"],
];

function totalScore(opportunity: Opportunity): number {
  return Object.values(opportunity.score).reduce((sum, value) => sum + value, 0);
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
      <p className={styles.stateLabel}>{eyebrow}</p>
      <h1>{title}</h1>
      <p>{body}</p>
      {action}
    </div>
  );
}

export function OpportunityDetail({ id, loadOpportunity = getOpportunityData, mutateDisposition = updateOpportunityDisposition }: OpportunityDetailProps) {
  const [state, setState] = useState<{ status: "loading" | "ready" | "error" | "unavailable"; data?: OpportunityData; message?: string }>({ status: "loading" });
  const [pending, setPending] = useState(false);
  const [mutationError, setMutationError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setState((current) => ({ ...current, status: "loading", message: undefined }));
    try {
      setState({ status: "ready", data: await loadOpportunity(id) });
    } catch (error) {
      const researchError = error instanceof ResearchClientError ? error : null;
      setState({
        status: researchError?.kind === "unavailable" ? "unavailable" : "error",
        message: researchError?.message ?? "The opportunity could not be loaded.",
      });
    }
  }, [id, loadOpportunity]);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  async function changeDisposition(disposition: OpportunityDisposition) {
    if (!state.data || pending || state.data.opportunity.disposition === disposition) return;
    const previous = state.data;
    const optimistic: OpportunityData = {
      ...previous,
      opportunity: {
        ...previous.opportunity,
        disposition,
        dispositionUpdatedAt: new Date().toISOString(),
      },
    };
    setMutationError(null);
    setPending(true);
    setState({ status: "ready", data: optimistic });
    try {
      const result = await mutateDisposition(id, disposition);
      if (result && typeof result === "object" && "disposition" in result) {
        const canonical = result as { disposition: OpportunityDisposition; changedAt: string };
        setState({
          status: "ready",
          data: {
            ...optimistic,
            opportunity: {
              ...optimistic.opportunity,
              disposition: canonical.disposition,
              dispositionUpdatedAt: canonical.changedAt,
            },
          },
        });
      }
    } catch {
      setState({ status: "ready", data: previous });
      setMutationError("That change could not be saved. The previous state has been restored.");
    } finally {
      setPending(false);
    }
  }

  if (state.status === "loading") {
    return <div className={styles.page}><StatePanel eyebrow="DATA STATE / LOADING" title="Reading opportunity evidence" body="The authenticated gateway is loading the original source and research brief." /></div>;
  }

  if (state.status !== "ready" || !state.data) {
    return (
      <div className={styles.page}>
        <Link className={styles.backLink} href="/today"><ArrowLeft aria-hidden="true" size={15} strokeWidth={1.6} /> Back to Today</Link>
        <StatePanel
          eyebrow={state.status === "unavailable" ? "DATA STATE / UNAVAILABLE" : "DATA STATE / ERROR"}
          title={state.status === "unavailable" ? "The research gateway is unavailable" : "Opportunity detail could not be loaded"}
          body={state.message ?? "The response did not arrive. Try again when the private gateway is reachable."}
          action={<button className={styles.retry} type="button" onClick={() => void load()}>Try again</button>}
        />
      </div>
    );
  }

  const { opportunity } = state.data;
  const originalSource = opportunity.originalSource;

  return (
    <div className={styles.page}>
      <Link className={styles.backLink} href="/today"><ArrowLeft aria-hidden="true" size={15} strokeWidth={1.6} /> Back to Today</Link>
      <header className={styles.header}>
        <p className={styles.eyebrow}>Opportunity detail / {opportunity.topicKey}</p>
        <h1 className={styles.title} dir={isArabicText(opportunity.title) ? "rtl" : "auto"}>{opportunity.title}</h1>
        <p className={styles.brief} dir={isArabicText(opportunity.brief) ? "rtl" : "auto"}>{opportunity.brief}</p>
        <div className={styles.headerMeta} aria-label="Opportunity state">
          <span className={`${styles.badge} ${opportunity.isHighPriority ? styles.badgeUrgent : ""}`}>{opportunity.isHighPriority ? "High priority" : "Standard priority"}</span>
          <span className={styles.badge}>Verification: {opportunity.verification}</span>
          <span className={styles.badge}>Earliest evidence: {formatResearchDate(opportunity.earliestPublishedAt)}</span>
        </div>
      </header>
      <div className={styles.statusLine} role="status">
        <span>Evidence response: {state.data.dataTruth}</span>
        <span>Last disposition change: {formatResearchDate(opportunity.dispositionUpdatedAt)}</span>
        <span>All timestamps are retained from the server response.</span>
      </div>
      <div className={styles.actionBar} aria-label="Opportunity actions">
        {(Object.keys(actionLabels) as OpportunityDisposition[]).map((disposition) => {
          const Icon = actionIcons[disposition];
          return (
            <button
              key={disposition}
              className={`${styles.action} ${opportunity.disposition === disposition ? styles.selected : ""}`}
              type="button"
              disabled={pending}
              aria-pressed={opportunity.disposition === disposition}
              onClick={() => void changeDisposition(disposition)}
            >
              {pending && opportunity.disposition !== disposition ? <LoaderCircle aria-hidden="true" size={15} /> : <Icon aria-hidden="true" size={15} strokeWidth={1.6} />}
              {pending && opportunity.disposition === disposition ? "Saving..." : actionLabels[disposition]}
            </button>
          );
        })}
        {mutationError ? <p className={styles.mutationError} role="alert">{mutationError}</p> : null}
      </div>
      <div className={styles.sectionGrid}>
        <section className={styles.section} aria-labelledby="brief-heading">
          <div className={styles.sectionHeading}><h2 id="brief-heading">Original evidence</h2><span className={styles.sectionLabel}>{originalSource ? "Source identified" : "Source missing"}</span></div>
          <div className={styles.sectionBody}>
            {originalSource ? <OriginalSource source={originalSource} /> : <div className={styles.missing}><strong>Original source unavailable</strong>The server did not identify an original source for this opportunity.</div>}
          </div>
        </section>
        <section className={styles.section} aria-labelledby="score-heading">
          <div className={styles.sectionHeading}><h2 id="score-heading">Score breakdown</h2><span className={styles.sectionLabel}>Transparent factors</span></div>
          <div className={styles.sectionBody}><ScoreTable opportunity={opportunity} /></div>
        </section>
        <section className={styles.section} aria-labelledby="regional-heading">
          <div className={styles.sectionHeading}><h2 id="regional-heading">Regional reading</h2><span className={styles.sectionLabel}>Egypt and Gulf</span></div>
          <div className={styles.sectionBody}><p className={styles.explanation} dir={isArabicText(opportunity.regionalExplanation) ? "rtl" : "auto"}>{opportunity.regionalExplanation}</p></div>
        </section>
        <section className={styles.section} aria-labelledby="coverage-heading">
          <div className={styles.sectionHeading}><h2 id="coverage-heading">Arabic coverage</h2><span className={styles.sectionLabel}>Coverage gap</span></div>
          <div className={styles.sectionBody}><p className={styles.explanation} dir={isArabicText(opportunity.coverageExplanation) ? "rtl" : "auto"}>{opportunity.coverageExplanation}</p></div>
        </section>
      </div>
      <section className={`${styles.section} ${styles.sourceSection}`} aria-labelledby="sources-heading">
        <div className={styles.sectionHeading}><h2 id="sources-heading">Supporting source items</h2><span className={styles.sectionLabel}>{opportunity.items.length} attached</span></div>
        {opportunity.items.length > 0 ? <div className={styles.sourceList}>{opportunity.items.map((source) => <SourceItem key={source.id} source={source} />)}</div> : <p className={styles.emptyEvidence}>No supporting source items were returned. Missing evidence is shown as missing, not as zero.</p>}
      </section>
    </div>
  );
}

function OriginalSource({ source }: { source: NonNullable<Opportunity["originalSource"]> }) {
  return (
    <div className={styles.originalSource}>
      <p className={styles.label}>Earliest known source</p>
      <h3 dir={isArabicText(source.title) ? "rtl" : "auto"}>{source.title}</h3>
      <p className={styles.sourceTitle} dir={isArabicText(source.summary) ? "rtl" : "auto"}>{source.summary}</p>
      <div className={styles.sourceMeta}><span>{source.group}</span><span>{source.author}</span><span>{source.country} / {source.language}</span></div>
      <span className={styles.sourceMeta}>Published {formatResearchDate(source.publishedAt)} / collected {formatResearchDate(source.collectedAt)}</span>
      <a className={styles.sourceLink} href={source.url} target="_blank" rel="noreferrer">Open original source <ExternalLink aria-hidden="true" size={13} strokeWidth={1.6} /></a>
    </div>
  );
}

function ScoreTable({ opportunity }: { opportunity: Opportunity }) {
  return (
    <>
      <table className={styles.scoreTable}><tbody>{scoreLabels.map(([key, label]) => <tr key={key}><th scope="row">{label}</th><td>{opportunity.score[key]}</td></tr>)}</tbody></table>
      <div className={styles.totalScore}><span className={styles.label}>Total research score</span><strong>{totalScore(opportunity)}</strong></div>
    </>
  );
}

function SourceItem({ source }: { source: NonNullable<Opportunity["items"]>[number] }) {
  return (
    <article className={styles.sourceItem}>
      <div>
        <h3 dir={isArabicText(source.title) ? "rtl" : "auto"}>{source.title}</h3>
        <p className={styles.sourceSummary} dir={isArabicText(source.summary) ? "rtl" : "auto"}>{source.summary}</p>
        <a className={styles.sourceLink} href={source.url} target="_blank" rel="noreferrer">Open source <ExternalLink aria-hidden="true" size={13} strokeWidth={1.6} /></a>
      </div>
      <div className={styles.sourceFacts}><span>{source.isOriginalSource ? "Original source" : "Supporting source"}</span><span>{source.group}</span><span>{source.author}</span><span>{source.country} / {source.language}</span><span>Published {formatResearchDate(source.publishedAt)}</span><span>Collected {formatResearchDate(source.collectedAt)}</span></div>
    </article>
  );
}
