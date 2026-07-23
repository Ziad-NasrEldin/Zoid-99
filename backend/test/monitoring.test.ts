import assert from "node:assert/strict";
import test from "node:test";
import { reportMonitoringEvent } from "../src/monitoring.js";

test("error monitoring sends only allowlisted operational metadata", async () => {
  let body = "";
  await reportMonitoringEvent({
    endpoint: "https://monitoring.example.test/hook",
    event: "collection_cycle_failed",
    serviceVersion: "test-sha",
    fetchImplementation: async (_input, init) => {
      body = String(init?.body);
      return new Response("", { status: 200 });
    },
  });

  const payload = JSON.parse(body) as Record<string, unknown>;
  assert.equal(payload.event, "collection_cycle_failed");
  assert.equal(payload.version, "test-sha");
  assert.deepEqual(Object.keys(payload).sort(), ["event", "occurredAt", "service", "version"]);
});
