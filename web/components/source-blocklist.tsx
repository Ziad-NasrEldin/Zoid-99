"use client";

import { FormEvent, useEffect, useState } from "react";

import { normalizeSourceDomain, readSourceBlocklist, writeSourceBlocklist } from "@/lib/source-blocklist";
import styles from "./source-blocklist.module.css";

export function SourceBlocklist() {
  const [domains, setDomains] = useState<string[]>([]);
  const [input, setInput] = useState("");
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => setDomains(readSourceBlocklist()), []);

  function save(next: string[]) {
    writeSourceBlocklist(next);
    setDomains(next);
  }

  function block(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const domain = normalizeSourceDomain(input);
    if (!domain) {
      setMessage("Enter a valid domain or URL.");
      return;
    }
    if (domains.includes(domain)) {
      setMessage(`${domain} is already blocked.`);
      return;
    }
    save([...domains, domain].sort());
    setInput("");
    setMessage(`${domain} is blocked in this browser.`);
  }

  return (
    <section className={styles.panel} aria-labelledby="source-blocklist-title">
      <div>
        <p className="page-eyebrow">SOURCE CONTROL</p>
        <h2 id="source-blocklist-title">Blocked sources</h2>
        <p>Hide research from a domain in Today and Radar. This browser keeps the list locally.</p>
      </div>
      <form onSubmit={block} className={styles.form}>
        <label htmlFor="source-domain">Domain or URL</label>
        <div className={styles.controls}>
          <input id="source-domain" value={input} onChange={(event) => setInput(event.target.value)} placeholder="example.com" />
          <button type="submit">Block source</button>
        </div>
      </form>
      {message ? <p className={styles.message} role="status">{message}</p> : null}
      {domains.length === 0 ? <p className={styles.empty}>No sources are blocked.</p> : (
        <ul className={styles.list}>
          {domains.map((domain) => <li key={domain}><code>{domain}</code><button type="button" onClick={() => { save(domains.filter((item) => item !== domain)); setMessage(`${domain} is no longer blocked.`); }}>Unblock</button></li>)}
        </ul>
      )}
    </section>
  );
}
