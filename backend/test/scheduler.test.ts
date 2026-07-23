import assert from "node:assert/strict";
import test from "node:test";
import { CollectionScheduler } from "../src/scheduler.js";

test("the collection scheduler runs immediately and never overlaps slow collection cycles", async () => {
  let releases = 0;
  let active = 0;
  let maximumActive = 0;
  const scheduler = new CollectionScheduler({
    intervalMilliseconds: 5,
    runCollection: async () => {
      active += 1;
      maximumActive = Math.max(maximumActive, active);
      await new Promise<void>((resolve) => setTimeout(resolve, 18));
      active -= 1;
      releases += 1;
    },
  });

  scheduler.start();
  await new Promise<void>((resolve) => setTimeout(resolve, 50));
  await scheduler.stop();

  assert.equal(maximumActive, 1);
  assert.ok(releases >= 2);
});

test("a failed cycle is reported and later cycles continue", async () => {
  let attempts = 0;
  const failures: unknown[] = [];
  const scheduler = new CollectionScheduler({
    intervalMilliseconds: 5,
    runCollection: async () => {
      attempts += 1;
      if (attempts === 1) throw new Error("provider unavailable");
    },
    onError: (error) => failures.push(error),
  });

  scheduler.start();
  await new Promise<void>((resolve) => setTimeout(resolve, 25));
  await scheduler.stop();

  assert.equal(failures.length, 1);
  assert.ok(attempts >= 2);
});
