export type MonitoringEvent = "collection_cycle_failed" | "backend_startup_failed";

export async function reportMonitoringEvent(options: {
  endpoint: string | undefined;
  event: MonitoringEvent;
  serviceVersion: string;
  fetchImplementation?: typeof fetch;
}): Promise<void> {
  if (!options.endpoint) return;
  const fetchImplementation = options.fetchImplementation ?? fetch;
  const response = await fetchImplementation(options.endpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      service: "zoid99-backend",
      version: options.serviceVersion,
      event: options.event,
      occurredAt: new Date().toISOString(),
    }),
    signal: AbortSignal.timeout(5_000),
  });
  if (!response.ok) throw new Error(`Monitoring endpoint returned HTTP ${response.status}`);
}
