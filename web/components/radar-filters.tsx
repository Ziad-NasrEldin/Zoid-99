"use client";

import { RotateCcw, Search, SlidersHorizontal } from "lucide-react";

import { radarFilterOptions, type RadarFilters } from "@/lib/radar-client";

import styles from "./radar-page.module.css";

type RadarFiltersProps = {
  value: RadarFilters;
  onChange: (value: RadarFilters) => void;
  onSubmit: () => void;
  onReset: () => void;
};

function fieldLabel(value: string, fallback: string): string {
  return value || fallback;
}

export function RadarFilters({ value, onChange, onSubmit, onReset }: RadarFiltersProps) {
  const set = (key: keyof RadarFilters, next: string) => {
    onChange({ ...value, [key]: next, cursor: "" });
  };

  return (
    <form className={styles.filterPanel} aria-label="Radar filters" onSubmit={(event) => {
      event.preventDefault();
      onSubmit();
    }}>
      <div className={styles.filterHeading}>
        <span className={styles.filterTitle}><SlidersHorizontal aria-hidden="true" size={16} /> Refine radar</span>
        <button className={styles.textButton} type="button" onClick={onReset}>
          <RotateCcw aria-hidden="true" size={14} /> Reset filters
        </button>
      </div>
      <div className={styles.filterGrid}>
        <label className={`${styles.field} ${styles.searchField}`}>
          <span>Search research</span>
          <span className={styles.inputWithIcon}>
            <Search aria-hidden="true" size={16} />
            <input
              aria-label="Search research"
              value={value.search}
              onChange={(event) => set("search", event.target.value)}
              maxLength={200}
              placeholder="Title, brief, or evidence"
            />
          </span>
        </label>
        <label className={styles.field}>
          <span>Source</span>
          <select aria-label="Source" value={value.source} onChange={(event) => set("source", event.target.value)}>
            <option value="">All sources</option>
            {radarFilterOptions.sources.map((option) => <option key={option} value={option}>{option}</option>)}
          </select>
        </label>
        <label className={styles.field}>
          <span>Topic</span>
          <input aria-label="Topic" value={value.topic} onChange={(event) => set("topic", event.target.value)} maxLength={200} placeholder="Topic key" />
        </label>
        <label className={styles.field}>
          <span>Country</span>
          <input aria-label="Country" value={value.country} onChange={(event) => set("country", event.target.value)} maxLength={100} placeholder="EG, US, ..." />
        </label>
        <label className={styles.field}>
          <span>Language</span>
          <input aria-label="Language" value={value.language} onChange={(event) => set("language", event.target.value)} maxLength={100} placeholder="ar, en, ..." />
        </label>
        <label className={styles.field}>
          <span>Freshness</span>
          <select aria-label="Freshness" value={value.freshness} onChange={(event) => set("freshness", event.target.value)}>
            <option value="">Any age</option>
            {radarFilterOptions.freshness.map((option) => <option key={option} value={option}>{fieldLabel(option, "Any age")}</option>)}
          </select>
        </label>
        <label className={styles.field}>
          <span>Verification</span>
          <select aria-label="Verification" value={value.verification} onChange={(event) => set("verification", event.target.value)}>
            <option value="">All truth states</option>
            {radarFilterOptions.verifications.map((option) => <option key={option} value={option}>{option}</option>)}
          </select>
        </label>
        <label className={styles.field}>
          <span>Disposition</span>
          <select aria-label="Disposition" value={value.disposition} onChange={(event) => set("disposition", event.target.value)}>
            <option value="">All dispositions</option>
            {radarFilterOptions.dispositions.map((option) => <option key={option} value={option}>{option}</option>)}
          </select>
        </label>
      </div>
      <div className={styles.filterActions}>
        <button className={styles.primaryButton} type="submit"><Search aria-hidden="true" size={16} /> Apply filters</button>
        <span className={styles.filterHint}>Up to 25 records per page</span>
      </div>
    </form>
  );
}
