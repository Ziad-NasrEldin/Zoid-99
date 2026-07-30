import styles from "@/components/opportunity-detail/opportunity-detail.module.css";

export default function OpportunityLoading() {
  return (
    <div className={styles.page} aria-busy="true">
      <div className={styles.statePanel}>
        <p className={styles.stateLabel}>DATA STATE / LOADING</p>
        <h1>Reading opportunity evidence</h1>
        <p>The authenticated gateway is loading the original source and research brief.</p>
      </div>
    </div>
  );
}
