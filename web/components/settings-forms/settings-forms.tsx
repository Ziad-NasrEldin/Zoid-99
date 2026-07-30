"use client";

import { useActionState } from "react";

import type { ConnectionStatus, Preferences } from "@zoid99/contracts";

import {
  configureConnection,
  disconnectConnection,
  savePreferences,
  validateConnection,
} from "@/app/settings/actions";
import {
  idleConnectionActionState,
  idlePreferenceActionState,
  type ConnectionActionState,
} from "@/lib/settings-client";

import styles from "./settings-forms.module.css";

type SettingsFormsProps = {
  connections: ConnectionStatus[];
  preferences: Preferences | null;
  etag: string | null;
  loadError: string | null;
};

const providerLabels: Record<ConnectionStatus["provider"], string> = {
  "google-trends": "Google Trends",
  "ai-provider": "AI provider",
};

function formatDate(value: string | null): string {
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

function ActionStatus({ state }: { state: ConnectionActionState }) {
  if (state.status === "idle") return null;
  return (
    <p className={state.status === "success" ? styles.success : styles.error} role="status" aria-live="polite">
      {state.message}
    </p>
  );
}

function ConnectionCard({ connection }: { connection: ConnectionStatus }) {
  const [configureState, configureAction, configurePending] = useActionState(
    configureConnection,
    idleConnectionActionState,
  );
  const [validateState, validateAction, validatePending] = useActionState(
    validateConnection,
    idleConnectionActionState,
  );
  const [disconnectState, disconnectAction, disconnectPending] = useActionState(
    disconnectConnection,
    idleConnectionActionState,
  );
  const current = disconnectState.connection ?? validateState.connection ?? configureState.connection ?? connection;

  return (
    <article className={styles.connectionCard} id={connection.provider}>
      <div className={styles.connectionHeader}>
        <div>
          <p className="page-eyebrow">SERVER CONNECTION</p>
          <h3>{providerLabels[connection.provider]}</h3>
        </div>
        <span className={styles.connectionState}>{current.state}</span>
      </div>
      <dl className={styles.details}>
        <div>
          <dt>Evidence</dt>
          <dd>{current.evidence}</dd>
        </div>
        <div>
          <dt>Last activity</dt>
          <dd>{formatDate(current.lastActivity)}</dd>
        </div>
        <div>
          <dt>Repair action</dt>
          <dd>{current.repairAction}</dd>
        </div>
      </dl>

      <div className={styles.actionArea}>
        <form key={configureState.formKey} action={configureAction} className={styles.configureForm}>
          <input type="hidden" name="provider" value={connection.provider} readOnly />
          <label htmlFor={`${connection.provider}-credential`}>Server credential</label>
          <input
            id={`${connection.provider}-credential`}
            name="credential"
            type="password"
            autoComplete="new-password"
            placeholder="Enter a new credential"
            aria-describedby={`${connection.provider}-credential-help`}
          />
          <p id={`${connection.provider}-credential-help`} className={styles.helpText}>
            Submitted only to the private server gateway. This field is never restored after submission.
          </p>
          <button type="submit" disabled={configurePending}>
            {configurePending ? "Checking and saving..." : "Configure and validate"}
          </button>
          <ActionStatus state={configureState} />
        </form>

        <div className={styles.secondaryActions}>
          <form action={validateAction}>
            <input type="hidden" name="provider" value={connection.provider} readOnly />
            <button type="submit" disabled={validatePending}>
              {validatePending ? "Validating..." : "Validate current credential"}
            </button>
          </form>
          <form action={disconnectAction}>
            <input type="hidden" name="provider" value={connection.provider} readOnly />
            <button
              type="submit"
              className={styles.dangerButton}
              disabled={disconnectPending}
              onClick={(event) => {
                if (!window.confirm(`Disconnect ${providerLabels[connection.provider]}?`)) event.preventDefault();
              }}
            >
              {disconnectPending ? "Disconnecting..." : "Disconnect"}
            </button>
          </form>
          <ActionStatus state={validateState} />
          <ActionStatus state={disconnectState} />
        </div>
      </div>
    </article>
  );
}

function PreferenceForm({ preferences, etag }: { preferences: Preferences; etag: string }) {
  const [state, formAction, pending] = useActionState(savePreferences, idlePreferenceActionState);
  const current = state.preferences ?? preferences;
  const currentETag = state.etag ?? etag;

  return (
    <form key={currentETag} action={formAction} className={styles.preferenceForm}>
      <input type="hidden" name="etag" value={currentETag} readOnly />
      <div className={styles.preferenceGrid}>
        <label>
          Refresh cadence
          <select name="refreshMinutes" defaultValue={current.refreshMinutes}>
            {[5, 15, 30, 60].map((value) => <option value={value} key={value}>{value} minutes</option>)}
          </select>
        </label>
        <label>
          Digest hour
          <select name="digestHour" defaultValue={current.digestHour}>
            {Array.from({ length: 24 }, (_, value) => <option value={value} key={value}>{String(value).padStart(2, "0")}:00</option>)}
          </select>
        </label>
        <label>
          Interface locale
          <select name="locale" defaultValue={current.locale}>
            <option value="en">English</option>
            <option value="ar-EG">Arabic content / Egypt</option>
          </select>
        </label>
        <label>
          Display time zone
          <select name="timeZone" defaultValue={current.timeZone}>
            <option value="Africa/Cairo">Africa/Cairo</option>
            <option value="Asia/Riyadh">Asia/Riyadh</option>
            <option value="UTC">UTC</option>
          </select>
        </label>
      </div>
      <fieldset className={styles.fieldset}>
        <legend>Notifications</legend>
        <label className={styles.checkboxLabel}>
          <input type="checkbox" name="notificationsEnabled" defaultChecked={current.notificationsEnabled} />
          Enable immediate notifications and scheduled digest delivery
        </label>
      </fieldset>
      <fieldset className={styles.fieldset}>
        <legend>Quiet hours</legend>
        <label className={styles.checkboxLabel}>
          <input type="checkbox" name="quietHoursEnabled" defaultChecked={current.quietHours.enabled} />
          Pause immediate notifications during quiet hours
        </label>
        <div className={styles.timeGrid}>
          <label>Start <input type="time" name="quietHoursStart" defaultValue={current.quietHours.start} /></label>
          <label>End <input type="time" name="quietHoursEnd" defaultValue={current.quietHours.end} /></label>
        </div>
      </fieldset>
      <div className={styles.preferenceFooter}>
        <p className={styles.etagNote}>Concurrency protection: this form saves only against the version it loaded.</p>
        <button type="submit" disabled={pending}>{pending ? "Saving..." : "Save preferences"}</button>
      </div>
      {state.status !== "idle" ? (
        <div className={state.status === "success" ? styles.successBox : state.status === "conflict" ? styles.conflictBox : styles.errorBox} role="status" aria-live="polite">
          <strong>{state.status === "conflict" ? "Reload required" : state.status === "success" ? "Saved" : "Not saved"}</strong>
          <p>{state.message}</p>
          {state.status === "conflict" ? <button type="button" onClick={() => window.location.reload()}>Reload current preferences</button> : null}
        </div>
      ) : null}
    </form>
  );
}

export function SettingsForms({ connections, preferences, etag, loadError }: SettingsFormsProps) {
  return (
    <div className={styles.layout}>
      <section className={styles.section} id="connections" aria-labelledby="connections-title">
        <div className={styles.sectionHeading}>
          <div>
            <p className="page-eyebrow">09 / Provider access</p>
            <h2 id="connections-title">Connections</h2>
          </div>
          <p>Credentials are accepted only by server actions and are encrypted at rest by the backend.</p>
        </div>
        <aside className={styles.reauthBoundary}>
          <strong>Reauthentication boundary</strong>
          <p>
            Every configure, validate, and disconnect action re-checks your private access identity on the server.
            If that identity check has expired, reauthenticate through private access and submit again.
          </p>
        </aside>
        {loadError ? <p className={styles.errorBox} role="status">{loadError}</p> : null}
        <div className={styles.connectionList}>
          {connections.map((connection) => <ConnectionCard connection={connection} key={connection.provider} />)}
          {connections.length === 0 ? <p className={styles.empty}>No connection status was returned.</p> : null}
        </div>
      </section>

      <section className={styles.section} aria-labelledby="preferences-title">
        <div className={styles.sectionHeading}>
          <div>
            <p className="page-eyebrow">10 / Research rhythm</p>
            <h2 id="preferences-title">Preferences</h2>
          </div>
          <p>Refresh, quiet hours, digest timing, locale, and display time zone.</p>
        </div>
        {preferences && etag ? (
          <PreferenceForm preferences={preferences} etag={etag} />
        ) : (
          <p className={styles.errorBox} role="status">{loadError ?? "Preferences are unavailable."}</p>
        )}
      </section>
    </div>
  );
}

