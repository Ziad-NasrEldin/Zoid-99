import Link from "next/link";

import type { SourceHealth } from "@zoid99/contracts";

import styles from "./source-health-ledger.module.css";

type SourceHealthLedgerProps = {
  sourceHealth: SourceHealth[];
};

const SOURCE_ORDER: SourceHealth["group"][] = [
  "YouTube",
  "Google Trends",
  "Instagram",
  "Comments",
  "US & Official",
  "X",
];

const stateClass: Record<SourceHealth["state"], string> = {
  Connected: styles.connected,
  "Setup required": styles.setupRequired,
  Unavailable: styles.unavailable,
  "Rate limited": styles.rateLimited,
  Delayed: styles.delayed,
  Disconnected: styles.disconnected,
  Cached: styles.cached,
  Unsupported: styles.unsupported,
};

function formatLastActivity(value: string | null): string {
  if (!value) return "No activity recorded";
  return new Intl.DateTimeFormat("en-GB", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZoneName: "short",
  }).format(new Date(value));
}

function missingSourceHealth(group: SourceHealth["group"]): SourceHealth {
  return {
    group,
    state: "Unavailable",
    lastActivity: null,
    evidence: "The gateway did not return a health record for this source.",
    repairAction: "Refresh source health",
    dataTruth: "Missing",
  };
}

export function SourceHealthLedger({ sourceHealth }: SourceHealthLedgerProps) {
  const records = new Map(sourceHealth.map((record) => [record.group, record]));
  const orderedRecords = SOURCE_ORDER.map((group) => records.get(group) ?? missingSourceHealth(group));

  return (
    <section className={styles.ledger} aria-labelledby="source-health-title">
      <div className={styles.heading}>
        <div>
          <p className="page-eyebrow">HEALTH LEDGER / SIX SOURCES</p>
          <h2 id="source-health-title">Collection health</h2>
        </div>
        <p className={styles.count} aria-label={`${orderedRecords.length} source records`}>
          {orderedRecords.length} source records
        </p>
      </div>

      <ul className={styles.list}>
        {orderedRecords.map((record) => (
          <li className={styles.row} key={record.group}>
            <div className={styles.sourceName}>
              <h3>{record.group}</h3>
              <p className={styles.truth}>Data truth: {record.dataTruth}</p>
            </div>
            <div className={styles.stateCell}>
              <span className={`${styles.state} ${stateClass[record.state]}`}>
                <span aria-hidden="true" className={styles.stateMark} />
                {record.state}
              </span>
              <span className={styles.activity}>Last activity: {formatLastActivity(record.lastActivity)}</span>
            </div>
            <div className={styles.evidence}>
              <p className={styles.label}>Evidence</p>
              <p>{record.evidence}</p>
            </div>
            <div className={styles.repair}>
              <p className={styles.label}>Repair action</p>
              <Link
                href={record.repairAction === "Refresh source health" ? "/sources" : "/settings#connections"}
                className={styles.repairLink}
              >
                {record.repairAction}
                <span aria-hidden="true"> -&gt;</span>
              </Link>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
