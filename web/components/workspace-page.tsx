import React from "react";

import { EmptyState } from "@/components/empty-state";

export type WorkspacePageConfig = {
  section: string;
  title: string;
  description: string;
  columns: string[];
  emptyEyebrow: string;
  emptyTitle: string;
  emptyBody: string;
};

export function WorkspacePage({ config }: { config: WorkspacePageConfig }) {
  return (
    <div className="workspace-page">
      <header className="page-header">
        <div>
          <p className="page-eyebrow">{config.section}</p>
          <h1>{config.title}</h1>
          <p className="page-description">{config.description}</p>
        </div>
        <p className="page-state">STATE / AWAITING DATA</p>
      </header>

      <section className="ledger" aria-labelledby="ledger-heading">
        <div className="ledger-heading-row">
          <h2 id="ledger-heading">Research ledger</h2>
          <span className="ledger-count">Records unavailable</span>
        </div>
        <div className="ledger-columns" aria-hidden="true">
          {config.columns.map((column) => (
            <span key={column}>{column}</span>
          ))}
        </div>
        <EmptyState
          eyebrow={config.emptyEyebrow}
          title={config.emptyTitle}
          body={config.emptyBody}
        />
      </section>
    </div>
  );
}
