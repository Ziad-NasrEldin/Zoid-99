import assert from "node:assert/strict";
import test from "node:test";
import {
  assertPublicHTTPSURL,
  fetchPublicHTTPSWith,
  type PublicHostnameResolver,
} from "../src/outbound-http.js";

const resolver: PublicHostnameResolver = async (hostname) => {
  if (hostname === "public.example") return [{ address: "93.184.216.34", family: 4 }];
  if (hostname === "metadata.internal") return [{ address: "169.254.169.254", family: 4 }];
  return [{ address: hostname, family: hostname.includes(":") ? 6 : 4 }];
};

test("the outbound policy rejects local and private official-source targets", async () => {
  await assert.rejects(assertPublicHTTPSURL("https://localhost/feed", resolver), /not public/);
  await assert.rejects(assertPublicHTTPSURL("https://127.0.0.1/feed", resolver), /non-public/);
  await assert.rejects(assertPublicHTTPSURL("https://169.254.169.254/latest/meta-data", resolver), /non-public/);
  await assert.rejects(
    assertPublicHTTPSURL(
      "https://deprecated-relay.example/feed",
      async () => [{ address: "192.88.99.1", family: 4 }],
    ),
    /non-public/,
  );
  await assert.rejects(
    assertPublicHTTPSURL(
      "https://compatible.example/feed",
      async () => [{ address: "::127.0.0.1", family: 6 }],
    ),
    /non-public/,
  );
  await assert.rejects(
    assertPublicHTTPSURL(
      "https://site-local.example/feed",
      async () => [{ address: "fec0::1", family: 6 }],
    ),
    /non-public/,
  );
  await assert.rejects(
    assertPublicHTTPSURL(
      "https://documentation.example/feed",
      async () => [{ address: "3fff::1", family: 6 }],
    ),
    /non-public/,
  );
});

test("every redirect target is revalidated before a request is made", async () => {
  const requests: string[] = [];
  await assert.rejects(
    fetchPublicHTTPSWith(
      "https://public.example/feed",
      {},
      async (input) => {
        requests.push(String(input));
        return new Response("", {
          status: 302,
          headers: { location: "https://metadata.internal/latest/meta-data" },
        });
      },
      resolver,
    ),
    /not public|non-public/,
  );
  assert.deepEqual(requests, ["https://public.example/feed"]);
});

test("oversized official-source responses are rejected before parsing", async () => {
  await assert.rejects(
    fetchPublicHTTPSWith(
      "https://public.example/feed",
      {},
      async () => new Response("x".repeat(2 * 1024 * 1024 + 1), { status: 200 }),
      resolver,
    ),
    /size limit/,
  );
});
