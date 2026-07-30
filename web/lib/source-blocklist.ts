const storageKey = "zoid99.source-blocklist";

export function normalizeSourceDomain(input: string): string | null {
  const value = input.trim().toLowerCase();
  if (!value) return null;
  try {
    const url = new URL(value.includes("://") ? value : `https://${value}`);
    return url.hostname.replace(/^www\./, "") || null;
  } catch {
    return null;
  }
}

export function readSourceBlocklist(): string[] {
  if (typeof window === "undefined") return [];
  try {
    const value: unknown = JSON.parse(window.localStorage.getItem(storageKey) ?? "[]");
    if (!Array.isArray(value)) return [];
    const domains = value.reduce<string[]>((result, item) => {
      if (typeof item !== "string") return result;
      const domain = normalizeSourceDomain(item);
      if (domain) result.push(domain);
      return result;
    }, []);
    return [...new Set(domains)].sort();
  } catch {
    return [];
  }
}

export function writeSourceBlocklist(domains: string[]): void {
  window.localStorage.setItem(storageKey, JSON.stringify([...new Set(domains)].sort()));
}

export function isBlockedSourceURL(url: string, domains: readonly string[]): boolean {
  const domain = normalizeSourceDomain(url);
  return domain !== null && domains.some((blocked) => domain === blocked || domain.endsWith(`.${blocked}`));
}
