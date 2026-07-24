import { lookup } from "node:dns/promises";
import { request } from "node:https";
import { BlockList, isIP } from "node:net";

export type ResolvedAddress = { address: string; family: number };
export type PublicHostnameResolver = (hostname: string) => Promise<ResolvedAddress[]>;

export type BoundedHTTPResponse = {
  status: number;
  ok: boolean;
  body: string;
};

const maximumResponseBytes = 2 * 1024 * 1024;
const maximumRedirects = 3;
const globalUnicastIPv6 = new BlockList();
globalUnicastIPv6.addSubnet("2000::", 3, "ipv6");
const nonPublicIPv6 = new BlockList();
for (const [network, prefix] of [
  ["::", 96],
  ["::ffff:0:0", 96],
  ["64:ff9b::", 96],
  ["64:ff9b:1::", 48],
  ["100::", 64],
  ["2001::", 23],
  ["2001:db8::", 32],
  ["2002::", 16],
  ["3fff::", 20],
  ["fc00::", 7],
  ["fec0::", 10],
  ["fe80::", 10],
  ["ff00::", 8],
] as const) {
  nonPublicIPv6.addSubnet(network, prefix, "ipv6");
}

export async function assertPublicHTTPSURL(
  value: string,
  resolver: PublicHostnameResolver = resolveHostname,
): Promise<{ url: URL; address: ResolvedAddress }> {
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password) {
    throw new Error("Official source URLs must use HTTPS without embedded credentials");
  }
  const hostname = url.hostname.toLocaleLowerCase();
  if (
    hostname === "localhost"
    || hostname.endsWith(".localhost")
    || hostname.endsWith(".local")
    || hostname.endsWith(".internal")
  ) {
    throw new Error("Official source URL hostname is not public");
  }
  const addresses = await resolver(hostname);
  if (addresses.length === 0 || addresses.some((entry) => !isPublicAddress(entry.address))) {
    throw new Error("Official source URL resolved to a non-public address");
  }
  return { url, address: addresses[0]! };
}

export async function fetchPublicHTTPS(
  value: string,
  headers: Record<string, string>,
  resolver: PublicHostnameResolver = resolveHostname,
  redirectsRemaining = maximumRedirects,
): Promise<BoundedHTTPResponse> {
  const approved = await assertPublicHTTPSURL(value, resolver);
  const response = await requestPinned(approved.url, approved.address, headers);
  if (isRedirect(response.status) && response.location) {
    if (redirectsRemaining === 0) throw new Error("Official source exceeded the redirect limit");
    const target = new URL(response.location, approved.url).toString();
    return fetchPublicHTTPS(target, headers, resolver, redirectsRemaining - 1);
  }
  return { status: response.status, ok: response.status >= 200 && response.status < 300, body: response.body };
}

export async function fetchPublicHTTPSWith(
  value: string,
  headers: Record<string, string>,
  fetchImplementation: typeof fetch,
  resolver: PublicHostnameResolver = resolveHostname,
): Promise<BoundedHTTPResponse> {
  let current = value;
  for (let redirect = 0; redirect <= maximumRedirects; redirect += 1) {
    await assertPublicHTTPSURL(current, resolver);
    const response = await fetchImplementation(current, {
      headers,
      redirect: "manual",
      signal: AbortSignal.timeout(15_000),
    });
    if (isRedirect(response.status)) {
      const location = response.headers.get("location");
      if (!location) return { status: response.status, ok: false, body: "" };
      if (redirect === maximumRedirects) throw new Error("Official source exceeded the redirect limit");
      current = new URL(location, current).toString();
      continue;
    }
    return {
      status: response.status,
      ok: response.ok,
      body: await readBoundedResponse(response),
    };
  }
  throw new Error("Official source exceeded the redirect limit");
}

export async function readBoundedResponse(response: Response): Promise<string> {
  if (!response.body) return "";
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const result = await reader.read();
    if (result.done) break;
    size += result.value.byteLength;
    if (size > maximumResponseBytes) {
      await reader.cancel();
      throw new Error("Provider response exceeded the size limit");
    }
    chunks.push(result.value);
  }
  const body = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(body);
}

function requestPinned(
  url: URL,
  approvedAddress: ResolvedAddress,
  headers: Record<string, string>,
): Promise<{ status: number; location: string | undefined; body: string }> {
  return new Promise((resolve, reject) => {
    const client = request({
      protocol: "https:",
      hostname: url.hostname,
      port: url.port || 443,
      path: `${url.pathname}${url.search}`,
      method: "GET",
      headers,
      servername: url.hostname,
      timeout: 15_000,
      lookup: (_hostname, _options, callback) => {
        callback(null, approvedAddress.address, approvedAddress.family);
      },
    }, (response) => {
      const chunks: Buffer[] = [];
      let size = 0;
      response.on("data", (chunk: Buffer) => {
        size += chunk.length;
        if (size > maximumResponseBytes) {
          client.destroy(new Error("Official source response exceeded the size limit"));
          return;
        }
        chunks.push(chunk);
      });
      response.on("end", () => resolve({
        status: response.statusCode ?? 0,
        location: response.headers.location,
        body: Buffer.concat(chunks).toString("utf8"),
      }));
      response.on("error", reject);
    });
    client.on("timeout", () => client.destroy(new Error("Official source request timed out")));
    client.on("error", reject);
    client.end();
  });
}

async function resolveHostname(hostname: string): Promise<ResolvedAddress[]> {
  return lookup(hostname, { all: true, verbatim: true });
}

function isRedirect(status: number): boolean {
  return [301, 302, 303, 307, 308].includes(status);
}

function isPublicAddress(address: string): boolean {
  const family = isIP(address);
  if (family === 4) {
    const octets = address.split(".").map(Number);
    const [first, second, third] = octets;
    if (first === undefined || second === undefined || third === undefined) return false;
    return !(
      first === 0
      || first === 10
      || first === 127
      || (first === 100 && second >= 64 && second <= 127)
      || (first === 169 && second === 254)
      || (first === 172 && second >= 16 && second <= 31)
      || (first === 192 && second === 0)
      || (first === 192 && second === 88 && third === 99)
      || (first === 192 && second === 168)
      || (first === 198 && (second === 18 || second === 19))
      || (first === 198 && second === 51)
      || (first === 203 && second === 0)
      || first >= 224
    );
  }
  if (family === 6) {
    return globalUnicastIPv6.check(address, "ipv6") && !nonPublicIPv6.check(address, "ipv6");
  }
  return false;
}
