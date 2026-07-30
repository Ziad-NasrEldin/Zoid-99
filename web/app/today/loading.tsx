import styles from "@/components/today-research/today.module.css";

export default function TodayLoading() {
  return (
    <div className={styles.page} aria-busy="true">
      <section className={styles.ledger} aria-label="Loading Today research">
        <div className={styles.statePanel}>
          <span className={styles.statusLabel}>DATA STATE / LOADING</span>
          <h2>Reading the research ledger</h2>
          <p>The authenticated gateway is checking the latest server-backed evidence.</p>
        </div>
      </section>
    </div>
  );
}
