"use client";

import { ArrowRight, Eye, EyeOff, LockKeyhole } from "lucide-react";
import { useState, type FormEvent } from "react";

export function OperatorLogin({ nextPath = "/today" }: { nextPath?: string }) {
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending || !password) return;
    setPending(true);
    setError(null);
    try {
      const response = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ password }),
      });
      const body = await response.json().catch(() => null) as { message?: unknown } | null;
      if (!response.ok) {
        setError(typeof body?.message === "string" ? body.message : "Access could not be verified.");
        return;
      }
      window.location.assign(nextPath);
    } catch {
      setError("Operator authentication is temporarily unavailable.");
    } finally {
      setPending(false);
    }
  }

  return (
    <main className="operator-login-shell" aria-label="Zoid 99 private operator access">
      <header className="operator-login-mast">
        <span className="operator-login-wordmark">ZOID 99</span>
        <span>PRIVATE RESEARCH LEDGER</span>
      </header>
      <div className="operator-login-stage">
        <aside className="operator-login-brand" aria-hidden="true">
          <span className="operator-login-index">99</span>
          <span className="operator-login-rule" />
          <span>Signals / Evidence / Timing</span>
        </aside>
        <section className="operator-login-panel" aria-busy={pending}>
          <div className="operator-login-icon"><LockKeyhole aria-hidden="true" size={20} strokeWidth={1.5} /></div>
          <p className="operator-login-kicker">Operator access</p>
          <h1>Enter Zoid 99</h1>
          <p className="operator-login-summary">Private research intelligence for one approved operator.</p>
          <form className="operator-login-form" onSubmit={submit}>
            <label htmlFor="operator-password">Operator password</label>
            <div className="operator-password-field">
              <input
                autoComplete="current-password"
                autoFocus
                disabled={pending}
                id="operator-password"
                maxLength={512}
                onChange={(event) => setPassword(event.currentTarget.value)}
                required
                type={showPassword ? "text" : "password"}
                value={password}
              />
              <button
                aria-label={showPassword ? "Hide password" : "Show password"}
                className="operator-password-toggle"
                disabled={pending}
                onClick={() => setShowPassword((visible) => !visible)}
                title={showPassword ? "Hide password" : "Show password"}
                type="button"
              >
                {showPassword
                  ? <EyeOff aria-hidden="true" size={17} strokeWidth={1.6} />
                  : <Eye aria-hidden="true" size={17} strokeWidth={1.6} />}
              </button>
            </div>
            <button className="operator-login-submit" disabled={pending || !password} type="submit">
              <span>{pending ? "Checking access" : "Enter workspace"}</span>
              <ArrowRight aria-hidden="true" size={17} strokeWidth={1.6} />
            </button>
          </form>
          {error ? <p className="operator-login-error" role="alert">{error}</p> : null}
        </section>
      </div>
      <footer className="operator-login-footer">
        <span>ZOID / 99</span>
        <span>CAIRO</span>
      </footer>
    </main>
  );
}
