import { SettingsForms } from "@/components/settings-forms/settings-forms";
import { gatewayRequest } from "@/lib/server/gateway";
import { parseConnectionsPayload, parsePreferencesPayload } from "@/lib/settings-client";

export const dynamic = "force-dynamic";

const settingsUnavailable = "Settings are unavailable from the private data gateway.";

async function loadSettings() {
  const [connectionsResult, preferencesResult] = await Promise.allSettled([
    gatewayRequest("/v1/connections", { cache: "no-store" }),
    gatewayRequest("/v1/preferences", { cache: "no-store" }),
  ]);

  let connections;
  let preferences;
  let etag;
  let error = "";

  if (connectionsResult.status === "fulfilled" && connectionsResult.value.ok) {
    try {
      connections = parseConnectionsPayload(await connectionsResult.value.json());
    } catch {
      error = settingsUnavailable;
    }
  } else {
    error = settingsUnavailable;
  }

  if (preferencesResult.status === "fulfilled" && preferencesResult.value.ok) {
    try {
      const parsed = parsePreferencesPayload(
        await preferencesResult.value.json(),
        preferencesResult.value.headers.get("etag"),
      );
      preferences = parsed.preferences;
      etag = parsed.etag;
    } catch {
      error = settingsUnavailable;
    }
  } else {
    error = settingsUnavailable;
  }

  return { connections, preferences, etag, error: error || null };
}

export default async function SettingsPage() {
  const settings = await loadSettings();

  return (
    <div className="workspace-page">
      <header className="page-header">
        <p className="page-eyebrow">08 / Configure</p>
        <h1>Settings</h1>
        <p className="page-description">
          Provider access and notification preferences stay server-managed and auditable.
        </p>
        <p className="page-state">SERVER SETTINGS / CONFLICT-SAFE</p>
      </header>
      <SettingsForms
        connections={settings.connections ?? []}
        preferences={settings.preferences ?? null}
        etag={settings.etag ?? null}
        loadError={settings.error}
      />
    </div>
  );
}

