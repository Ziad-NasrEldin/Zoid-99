import { EmptyState } from "@/components/empty-state";
import { SourceHealthLedger } from "@/components/source-health-ledger/source-health-ledger";
import { gatewayRequest } from "@/lib/server/gateway";
import { parseSourceHealthPayload } from "@/lib/settings-client";

export const dynamic = "force-dynamic";

const sourceHealthUnavailable = "Source health is unavailable from the private data gateway.";

async function loadSourceHealth() {
  try {
    const response = await gatewayRequest("/v1/sources/health", { cache: "no-store" });
    if (!response.ok) return { error: sourceHealthUnavailable };
    return { sourceHealth: parseSourceHealthPayload(await response.json()) };
  } catch {
    return { error: sourceHealthUnavailable };
  }
}

export default async function SourcesPage() {
  const result = await loadSourceHealth();

  return (
    <div className="workspace-page">
      <header className="page-header">
        <div>
          <p className="page-eyebrow">07 / Collection truth</p>
          <h1>Sources</h1>
          <p className="page-description">
            A live ledger of collection health, recent evidence, and the next repair action.
          </p>
        </div>
        <p className="page-state">SERVER LEDGER / WRITTEN STATES</p>
      </header>
      {result.sourceHealth ? (
        <SourceHealthLedger sourceHealth={result.sourceHealth} />
      ) : (
        <section className="ledger" aria-labelledby="sources-unavailable-title">
          <div className="ledger-heading-row">
            <div>
              <p className="page-eyebrow">DATA STATE / UNAVAILABLE</p>
              <h2 id="sources-unavailable-title">Source health is not available</h2>
            </div>
          </div>
          <EmptyState
            eyebrow="GATEWAY / NO RESPONSE"
            title="No source health was returned"
            body={result.error ?? sourceHealthUnavailable}
          />
        </section>
      )}
    </div>
  );
}
