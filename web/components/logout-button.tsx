"use client";

import { LogOut } from "lucide-react";
import { useState } from "react";

export function LogoutButton({ compact = false }: { compact?: boolean }) {
  const [pending, setPending] = useState(false);

  async function logout() {
    if (pending) return;
    setPending(true);
    try {
      await fetch("/api/auth/logout", { method: "POST" });
    } finally {
      window.location.assign("/login");
    }
  }

  return (
    <button
      className={`logout-button${compact ? " is-compact" : ""}`}
      disabled={pending}
      onClick={logout}
      title="Sign out"
      type="button"
    >
      <LogOut aria-hidden="true" size={15} strokeWidth={1.6} />
      <span>{pending ? "Signing out" : "Sign out"}</span>
    </button>
  );
}
