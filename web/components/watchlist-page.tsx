"use client";

import { useEffect, useMemo, useState } from "react";
import { Check, ChevronDown, LoaderCircle, Pencil, Plus, RotateCcw, Star, Trash2, X } from "lucide-react";
import type { WatchlistEntry, WatchlistKind } from "@zoid99/contracts";
import {
  duplicateWatchlistEntry,
  providerSupport,
  providerSupportForKind,
  type WatchlistClient,
  type WatchlistInput,
  validateWatchlistInput,
  watchlistClient,
  watchlistKindLabels,
  watchlistKinds,
  WatchlistClientError,
} from "@/lib/watchlist-client";
import styles from "./watchlist-page.module.css";

type MutationState = { key: string; status: "pending" | "success" | "error" } | null;

type WatchlistPageProps = {
  client?: WatchlistClient;
};

const blankDraft: WatchlistInput = { kind: "Creator", value: "", highPriority: false };

function makeOptimisticID(): string {
  return globalThis.crypto?.randomUUID?.() ?? `00000000-0000-4000-8000-${Date.now().toString().padStart(12, "0").slice(-12)}`;
}

function friendlyError(error: unknown): string {
  if (error instanceof WatchlistClientError) return error.message;
  return "The change could not be saved. Your previous watchlist was restored.";
}

export function WatchlistPage({ client = watchlistClient }: WatchlistPageProps) {
  const [entries, setEntries] = useState<WatchlistEntry[]>([]);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "error" | "unavailable">("loading");
  const [loadError, setLoadError] = useState<string | null>(null);
  const [draft, setDraft] = useState<WatchlistInput>(blankDraft);
  const [editingID, setEditingID] = useState<string | null>(null);
  const [editingDraft, setEditingDraft] = useState<WatchlistInput>(blankDraft);
  const [mutation, setMutation] = useState<MutationState>(null);
  const [mutationError, setMutationError] = useState<string | null>(null);
  const [mutationNotice, setMutationNotice] = useState<string | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    client.list(controller.signal)
      .then((nextEntries) => {
        setEntries(nextEntries);
        setLoadState("ready");
      })
      .catch((error: unknown) => {
        if (controller.signal.aborted) return;
        setLoadError(friendlyError(error));
        setLoadState(error instanceof WatchlistClientError && error.kind === "unavailable" ? "unavailable" : "error");
      });
    return () => controller.abort();
  }, [client]);

  const priorityCount = useMemo(() => entries.filter((entry) => entry.highPriority).length, [entries]);
  const isMutating = mutation?.status === "pending";

  function announceSuccess(message: string) {
    setMutationError(null);
    setMutationNotice(message);
    window.setTimeout(() => setMutationNotice(null), 3500);
  }

  async function addEntry(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const input = { ...draft, value: draft.value.trim() };
    const validationError = validateWatchlistInput(input);
    if (validationError) {
      setMutationError(validationError);
      setMutationNotice(null);
      return;
    }
    if (duplicateWatchlistEntry(entries, input)) {
      setMutationError("That value is already on this watchlist.");
      setMutationNotice(null);
      return;
    }

    const optimisticID = makeOptimisticID();
    const previous = entries;
    const key = `add:${optimisticID}`;
    setEntries((current) => [...current, { id: optimisticID, ...input }]);
    setMutation({ key, status: "pending" });
    setMutationError(null);
    setMutationNotice(null);
    try {
      const saved = await client.add(input, key);
      setEntries((current) => current.map((entry) => entry.id === optimisticID ? saved : entry));
      setDraft(blankDraft);
      setMutation({ key, status: "success" });
      announceSuccess("Watchlist entry added and synced.");
    } catch (error) {
      setEntries(previous);
      setMutation({ key, status: "error" });
      setMutationError(friendlyError(error));
    }
  }

  function startEditing(entry: WatchlistEntry) {
    setEditingID(entry.id);
    setEditingDraft({ kind: entry.kind, value: entry.value, highPriority: entry.highPriority });
    setMutationError(null);
    setMutationNotice(null);
  }

  function cancelEditing() {
    setEditingID(null);
    setEditingDraft(blankDraft);
  }

  async function editEntry(entry: WatchlistEntry) {
    const input = { ...editingDraft, value: editingDraft.value.trim() };
    const validationError = validateWatchlistInput(input);
    if (validationError) {
      setMutationError(validationError);
      setMutationNotice(null);
      return;
    }
    if (duplicateWatchlistEntry(entries, input, entry.id)) {
      setMutationError("That value is already on this watchlist.");
      setMutationNotice(null);
      return;
    }

    const previous = entries;
    const key = `edit:${entry.id}:${makeOptimisticID()}`;
    setEntries((current) => current.map((currentEntry) => currentEntry.id === entry.id ? { ...currentEntry, ...input } : currentEntry));
    setMutation({ key, status: "pending" });
    setMutationError(null);
    setMutationNotice(null);
    try {
      const saved = await client.edit(entry.id, input, key);
      setEntries((current) => current.map((currentEntry) => currentEntry.id === entry.id ? saved : currentEntry));
      cancelEditing();
      setMutation({ key, status: "success" });
      announceSuccess("Watchlist entry edited and synced.");
    } catch (error) {
      setEntries(previous);
      setMutation({ key, status: "error" });
      setMutationError(friendlyError(error));
    }
  }

  async function togglePriority(entry: WatchlistEntry) {
    const nextPriority = !entry.highPriority;
    const previous = entries;
    const key = `priority:${entry.id}:${nextPriority}:${makeOptimisticID()}`;
    setEntries((current) => current.map((currentEntry) => currentEntry.id === entry.id ? { ...currentEntry, highPriority: nextPriority } : currentEntry));
    setMutation({ key, status: "pending" });
    setMutationError(null);
    setMutationNotice(null);
    try {
      const saved = await client.edit(entry.id, { kind: entry.kind, value: entry.value, highPriority: nextPriority }, key);
      setEntries((current) => current.map((currentEntry) => currentEntry.id === entry.id ? saved : currentEntry));
      setMutation({ key, status: "success" });
      announceSuccess(nextPriority ? "High priority enabled and synced." : "High priority cleared and synced.");
    } catch (error) {
      setEntries(previous);
      setMutation({ key, status: "error" });
      setMutationError(friendlyError(error));
    }
  }

  async function removeEntry(entry: WatchlistEntry) {
    const previous = entries;
    const key = `remove:${entry.id}:${makeOptimisticID()}`;
    setEntries((current) => current.filter((currentEntry) => currentEntry.id !== entry.id));
    setMutation({ key, status: "pending" });
    setMutationError(null);
    setMutationNotice(null);
    try {
      await client.remove(entry.id, key);
      setMutation({ key, status: "success" });
      announceSuccess("Watchlist entry removed and synced.");
    } catch (error) {
      setEntries(previous);
      setMutation({ key, status: "error" });
      setMutationError(friendlyError(error));
    }
  }

  function renderState() {
    if (loadState === "loading") {
      return <div className={styles.statePanel} role="status"><LoaderCircle className={styles.spinner} aria-hidden="true" size={22} /><strong>Loading watchlists</strong><span>Reading the private gateway.</span></div>;
    }
    if (loadState !== "ready") {
      return <div className={styles.statePanel} role="alert"><strong>{loadState === "unavailable" ? "Watchlists unavailable" : "Watchlists could not be loaded"}</strong><span>{loadError}</span><button type="button" className={styles.secondaryButton} onClick={() => window.location.reload()}><RotateCcw aria-hidden="true" size={15} />Try again</button></div>;
    }
    if (entries.length === 0) {
      return <div className={styles.statePanel}><strong>No watchlist entries yet</strong><span>Add a creator, official source, company, keyword, topic, country, or language to begin collection.</span></div>;
    }
    return <div className={styles.entryList}>{entries.map((entry) => <WatchlistCard key={entry.id} entry={entry} editing={editingID === entry.id} editingDraft={editingDraft} disabled={isMutating} onEditDraft={setEditingDraft} onStartEdit={() => startEditing(entry)} onCancelEdit={cancelEditing} onSaveEdit={() => void editEntry(entry)} onTogglePriority={() => void togglePriority(entry)} onRemove={() => void removeEntry(entry)} />)}</div>;
  }

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <div>
          <p className={styles.eyebrow}>07 / MONITOR</p>
          <h1>Watchlists</h1>
          <p className={styles.description}>Choose the signals Zoid 99 should collect, then mark the ones that deserve immediate attention.</p>
        </div>
        <div className={styles.headerMeta} aria-label="Watchlist summary">
          <span>{entries.length} {entries.length === 1 ? "entry" : "entries"}</span>
          <span>{priorityCount} high priority</span>
        </div>
      </header>

      <section className={styles.addSection} aria-labelledby="add-watchlist-heading">
        <div className={styles.sectionHeading}><div><p className={styles.eyebrow}>NEW SIGNAL</p><h2 id="add-watchlist-heading">Add to your watchlist</h2></div><Plus aria-hidden="true" size={20} /></div>
        <form className={styles.addForm} onSubmit={addEntry}>
          <label>Kind<select value={draft.kind} onChange={(event) => setDraft((current) => ({ ...current, kind: event.target.value as WatchlistKind }))}>{watchlistKinds.map((kind) => <option key={kind} value={kind}>{watchlistKindLabels[kind]}</option>)}</select></label>
          <label className={styles.valueField}>Value<input value={draft.value} maxLength={500} onChange={(event) => setDraft((current) => ({ ...current, value: event.target.value }))} placeholder={draft.kind === "Official source" ? "https://example.com/releases" : "Enter a value"} /></label>
          <label className={styles.priorityInput}><input type="checkbox" checked={draft.highPriority} onChange={(event) => setDraft((current) => ({ ...current, highPriority: event.target.checked }))} />High priority</label>
          <button type="submit" className={styles.primaryButton} disabled={isMutating}><Plus aria-hidden="true" size={16} />Add entry</button>
        </form>
        <p className={styles.supportHint}>This kind is collected by <strong>{providerSupportForKind(draft.kind)}</strong>. Provider credentials and connector setup are still required.</p>
      </section>

      <section className={styles.contentSection} aria-labelledby="configured-heading">
        <div className={styles.sectionHeading}><div><p className={styles.eyebrow}>CONFIGURED SIGNALS</p><h2 id="configured-heading">Your watchlist</h2></div><span className={styles.serverTruth}>Gateway-backed</span></div>
        {mutationError ? <p className={styles.errorNotice} role="alert">{mutationError}</p> : null}
        {mutationNotice ? <p className={styles.successNotice} role="status"><Check aria-hidden="true" size={15} />{mutationNotice}</p> : null}
        {mutation?.status === "pending" ? <p className={styles.syncNotice} role="status"><LoaderCircle className={styles.spinner} aria-hidden="true" size={15} />Saving this change...</p> : null}
        {renderState()}
      </section>

      <section className={styles.supportSection} aria-labelledby="support-heading">
        <div className={styles.sectionHeading}><div><p className={styles.eyebrow}>PROVIDER TRUTH</p><h2 id="support-heading">Where each signal can go</h2></div><ChevronDown aria-hidden="true" size={19} /></div>
        <div className={styles.supportGrid}>{providerSupport.map((provider) => <article className={styles.supportCard} key={provider.name}><div className={styles.supportName}><span className={provider.supportedKinds.length ? styles.supportedDot : styles.unsupportedDot} aria-hidden="true" />{provider.name}</div><strong>{provider.supportedKinds.length ? `${provider.supportedKinds.length} of 7 kinds` : "No watchlist kinds"}</strong><p>{provider.note}</p></article>)}</div>
      </section>
    </main>
  );
}

type WatchlistCardProps = {
  entry: WatchlistEntry;
  editing: boolean;
  editingDraft: WatchlistInput;
  disabled: boolean;
  onEditDraft: (draft: WatchlistInput) => void;
  onStartEdit: () => void;
  onCancelEdit: () => void;
  onSaveEdit: () => void;
  onTogglePriority: () => void;
  onRemove: () => void;
};

function WatchlistCard({ entry, editing, editingDraft, disabled, onEditDraft, onStartEdit, onCancelEdit, onSaveEdit, onTogglePriority, onRemove }: WatchlistCardProps) {
  return (
    <article className={styles.entryCard}>
      {editing ? (
        <div className={styles.editForm} aria-label={`Edit ${entry.value}`}>
          <label>Kind<select value={editingDraft.kind} onChange={(event) => onEditDraft({ ...editingDraft, kind: event.target.value as WatchlistKind })}>{watchlistKinds.map((kind) => <option key={kind} value={kind}>{watchlistKindLabels[kind]}</option>)}</select></label>
          <label className={styles.valueField}>Value<input value={editingDraft.value} maxLength={500} onChange={(event) => onEditDraft({ ...editingDraft, value: event.target.value })} /></label>
          <label className={styles.priorityInput}><input type="checkbox" checked={editingDraft.highPriority} onChange={(event) => onEditDraft({ ...editingDraft, highPriority: event.target.checked })} />High priority</label>
          <div className={styles.editActions}><button type="button" className={styles.primaryButton} onClick={onSaveEdit} disabled={disabled}><Check aria-hidden="true" size={15} />Save</button><button type="button" className={styles.secondaryButton} onClick={onCancelEdit} disabled={disabled}><X aria-hidden="true" size={15} />Cancel</button></div>
        </div>
      ) : (
        <div className={styles.cardLayout}>
          <div className={styles.entryDetails}><div className={styles.entryTopline}><span className={styles.kindBadge}>{watchlistKindLabels[entry.kind]}</span><span className={styles.supportLabel}>{providerSupportForKind(entry.kind)} <span className={styles.supportDivider}>/</span> connector support</span></div><h3>{entry.value}</h3><p>{entry.kind === "Official source" ? "Validated HTTPS source" : "Stored in the private research gateway"}</p></div>
          <div className={styles.cardActions} aria-label={`Actions for ${entry.value}`}><button type="button" className={`${styles.iconButton} ${entry.highPriority ? styles.priorityOn : ""}`} onClick={onTogglePriority} disabled={disabled} aria-pressed={entry.highPriority} aria-label={entry.highPriority ? `Clear high priority for ${entry.value}` : `Set high priority for ${entry.value}`} title={entry.highPriority ? "Clear high priority" : "Set high priority"}><Star aria-hidden="true" size={17} fill={entry.highPriority ? "currentColor" : "none"} /><span>{entry.highPriority ? "High priority" : "Priority"}</span></button><button type="button" className={styles.iconButton} onClick={onStartEdit} disabled={disabled}><Pencil aria-hidden="true" size={16} /><span>Edit</span></button><button type="button" className={`${styles.iconButton} ${styles.dangerButton}`} onClick={onRemove} disabled={disabled}><Trash2 aria-hidden="true" size={16} /><span>Remove</span></button></div>
        </div>
      )}
    </article>
  );
}
