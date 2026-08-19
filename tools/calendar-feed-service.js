import { createHash, randomBytes } from "node:crypto";
import { lookup } from "node:dns/promises";
import { open, readFile, rename, unlink } from "node:fs/promises";
import { request as httpsRequest } from "node:https";
import { isIP, BlockList } from "node:net";
import { join } from "node:path";

const MAX_CONFIG_BODY = 1024 * 1024;
const MAX_CALENDAR_BODY = 32 * 1024 * 1024;
const blocked = new BlockList();
for (const [address, prefix, family] of [
  ["0.0.0.0", 8, "ipv4"], ["10.0.0.0", 8, "ipv4"], ["100.64.0.0", 10, "ipv4"],
  ["127.0.0.0", 8, "ipv4"], ["169.254.0.0", 16, "ipv4"], ["172.16.0.0", 12, "ipv4"],
  ["192.0.0.0", 24, "ipv4"], ["192.0.2.0", 24, "ipv4"], ["192.168.0.0", 16, "ipv4"],
  ["198.18.0.0", 15, "ipv4"], ["198.51.100.0", 24, "ipv4"], ["203.0.113.0", 24, "ipv4"],
  ["224.0.0.0", 4, "ipv4"], ["240.0.0.0", 4, "ipv4"],
  ["::", 128, "ipv6"], ["::1", 128, "ipv6"], ["fc00::", 7, "ipv6"], ["fe80::", 10, "ipv6"],
  ["ff00::", 8, "ipv6"], ["2001:db8::", 32, "ipv6"]
]) blocked.addSubnet(address, prefix, family);

function json(response, status, value) {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  response.end(JSON.stringify(value));
}

function publicConnection(connection) {
  const url = new URL(connection.url);
  return { id: connection.id, label: connection.label, provider: "ics", urlHint: url.origin };
}

async function jsonBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_CONFIG_BODY) throw new RangeError("Calendar connection request is too large");
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

// `webcal://`/`webcals://` are the near-universal scheme publishers hand out
// for ICS subscription links; they are just HTTP(S)-transported iCalendar,
// so normalize them to `https://` before any validation runs. This is the
// single normalization chokepoint for the whole subscription path (feed
// creation and every re-pull both call `checkedUrl`), so a normalized URL
// is always subjected to the full HTTPS/target validation below — it is
// never a way around it. Plain `http://` is untouched and still rejected.
export function normalizeFeedUrlScheme(value) {
  return String(value || "").replace(/^webcals?:\/\//i, "https://");
}

function checkedUrl(value) {
  const url = new URL(normalizeFeedUrlScheme(value));
  if (url.protocol !== "https:") throw new Error("Calendar feed URLs must use HTTPS (webcal:// and webcals:// are accepted and treated the same as https://)");
  if (url.username || url.password) throw new Error("Put credentials in the feed's secret URL, not URL user-info fields");
  if (["localhost", "localhost.localdomain"].includes(url.hostname.toLowerCase()) || url.hostname.endsWith(".local")) {
    throw new Error("Calendar feeds cannot target this device or a private network");
  }
  return url;
}

function publicAddress(address, family) {
  const kind = family === 6 || family === "IPv6" ? "ipv6" : "ipv4";
  if (kind === "ipv6" && address.toLowerCase().startsWith("::ffff:")) {
    const mapped = address.slice(7);
    return isIP(mapped) === 4 && !blocked.check(mapped, "ipv4");
  }
  return !blocked.check(address, kind);
}

// `hostname` resolution is itself resolver-shaped and not a fixed contract:
// `dns.promises.lookup(host, {all:true})` answers with an array of
// `{address, family}` objects, while the classic single-address form is
// `(address, family)`. `resolveHost` defaults to the real DNS resolver but
// is overridable so tests can exercise the actual private/reserved-range
// guard below against stubbed answers without a live network call.
async function resolvedPublicAddress(hostname, resolveHost = lookup) {
  if (isIP(hostname)) {
    const family = isIP(hostname);
    if (!publicAddress(hostname, family)) throw new Error("Calendar feeds cannot target a private or reserved address");
    return { address: hostname, family };
  }
  const addresses = await resolveHost(hostname, { all: true, verbatim: true });
  const selected = addresses.find((entry) => publicAddress(entry.address, entry.family));
  if (!selected || addresses.some((entry) => !publicAddress(entry.address, entry.family))) {
    throw new Error("Calendar feed hostname resolves to a private or reserved address");
  }
  return selected;
}

// Node's own connection machinery calls a custom `lookup` option exactly
// like a DNS resolver, and that contract is not a fixed shape: Happy
// Eyeballs (`autoSelectFamily`, default-on since Node 20) asks for
// `options.all` and requires the callback in the array-of-`{address,
// family}` shape (the same shape `dns.promises.lookup` returns for
// `{all: true}`), while a plain connect asks for the classic single
// `(address, family)` shape. The DNS-pinned address here is always a
// single answer, but it must still be handed back in whichever shape was
// requested — answering unconditionally in the classic shape feeds Node's
// array-expecting path a bare number where it expects a list, which fails
// downstream with "Invalid IP address: undefined". This is the same
// resolver-shape contract `resolvedPublicAddress` honors on the resolution
// side above; `pinnedLookup` is the other end of it, exported so the shape
// contract itself is directly testable without a real socket.
export function pinnedLookup(address) {
  return function lookup(_hostname, options, callback) {
    if (options && options.all) callback(null, [{ address: address.address, family: address.family }]);
    else callback(null, address.address, address.family);
  };
}

function requestCalendar(url, address, headers) {
  return new Promise((resolveRequest, rejectRequest) => {
    const request = httpsRequest(url, {
      method: "GET",
      headers,
      lookup: pinnedLookup(address)
    }, (response) => {
      const chunks = [];
      let size = 0;
      response.on("data", (chunk) => {
        size += chunk.length;
        if (size > MAX_CALENDAR_BODY) {
          response.destroy(new RangeError("Calendar feed exceeds the 32 MiB sync limit"));
          return;
        }
        chunks.push(chunk);
      });
      response.once("error", rejectRequest);
      response.once("end", () => resolveRequest({
        status: response.statusCode || 0,
        headers: response.headers,
        body: Buffer.concat(chunks)
      }));
    });
    request.setTimeout(30_000, () => request.destroy(new Error("Calendar feed timed out")));
    request.once("error", rejectRequest);
    request.end();
  });
}

// `deps` overrides the DNS resolver and the HTTP transport for tests, so the
// full pipeline — webcal normalization, the private/reserved-range guard,
// and redirect-chain re-validation — is exercisable with stubbed answers and
// no live network call. Production callers never pass it; both default to
// the real implementations above. Redirects thread the same `deps` through
// every hop, which is what makes "each hop re-validated" actually true: a
// redirect to a private target re-enters `resolvedPublicAddress` with the
// same guard, not a bypass.
export async function pullHttpsCalendar(value, current = {}, redirects = 0, deps = {}) {
  const { resolveHost = lookup, sendRequest = requestCalendar } = deps;
  const url = checkedUrl(value);
  if (redirects > 5) throw new Error("Calendar feed redirected too many times");
  const address = await resolvedPublicAddress(url.hostname, resolveHost);
  const result = await sendRequest(url, address, {
    accept: "text/calendar, text/plain;q=0.8",
    "user-agent": "ChronoLog calendar sync",
    ...(current?.etag ? { "if-none-match": current.etag } : {}),
    ...(current?.lastModified ? { "if-modified-since": current.lastModified } : {})
  });
  if ([301, 302, 303, 307, 308].includes(result.status) && result.headers.location) {
    return pullHttpsCalendar(new URL(result.headers.location, url).href, current, redirects + 1, deps);
  }
  const revision = {
    etag: result.headers.etag || null,
    lastModified: result.headers["last-modified"] || null,
    digest: result.body.length ? createHash("sha256").update(result.body).digest("hex") : current?.digest || null
  };
  if (result.status === 304) return { notModified: true, revision };
  if (result.status !== 200) throw new Error(`Calendar feed returned HTTP ${result.status}`);
  const text = result.body.toString("utf8");
  if (!/(?:^|\r?\n)BEGIN:VCALENDAR(?:\r?\n|$)/i.test(text)) throw new Error("Remote response is not an ICS calendar");
  return {
    notModified: revision.digest === current?.digest,
    revision,
    text,
    contentType: result.headers["content-type"] || "text/calendar"
  };
}

export function createCalendarFeedService({ dataRoot, pullFeed = pullHttpsCalendar } = {}) {
  if (!dataRoot) throw new Error("Calendar feed service requires a data directory");
  const connectionsFile = join(dataRoot, ".chronolog-calendar-connections.json");

  async function readConnections() {
    try {
      const parsed = JSON.parse(await readFile(connectionsFile, "utf8"));
      return parsed?.version === 1 && parsed.feeds && typeof parsed.feeds === "object"
        ? parsed : { version: 1, feeds: {} };
    } catch (error) {
      if (error?.code === "ENOENT") return { version: 1, feeds: {} };
      throw error;
    }
  }

  async function writeConnections(value) {
    const temporary = join(dataRoot, `.chronolog-connections-${process.pid}-${Date.now()}.tmp`);
    const descriptor = await open(temporary, "wx", 0o600);
    try {
      await descriptor.writeFile(`${JSON.stringify(value, null, 2)}\n`);
      await descriptor.sync();
    } finally {
      await descriptor.close();
    }
    try { await rename(temporary, connectionsFile); }
    finally { await unlink(temporary).catch(() => {}); }
  }

  return async function handleCalendarFeed(request, response, url) {
    if (url.pathname === "/api/sync/connections" && request.method === "GET") {
      const connections = await readConnections();
      json(response, 200, { feeds: Object.values(connections.feeds).map(publicConnection) });
      return true;
    }
    if (url.pathname === "/api/sync/feeds" && request.method === "POST") {
      const input = await jsonBody(request);
      const remote = checkedUrl(input.url);
      const connections = await readConnections();
      const id = `feed:${randomBytes(12).toString("base64url")}`;
      const connection = { id, label: String(input.label || remote.hostname).trim() || remote.hostname, url: remote.href };
      connections.feeds[id] = connection;
      await writeConnections(connections);
      json(response, 201, publicConnection(connection));
      return true;
    }
    const match = /^\/api\/sync\/feeds\/([^/]+)(?:\/(pull))?$/.exec(url.pathname);
    if (!match) return false;
    const id = decodeURIComponent(match[1]);
    const connections = await readConnections();
    const connection = connections.feeds[id];
    if (!connection) {
      json(response, 404, { error: "Unknown calendar feed" });
      return true;
    }
    if (match[2] === "pull" && request.method === "POST") {
      const input = await jsonBody(request);
      const result = await pullFeed(connection.url, input.revision || {});
      json(response, 200, { connection: publicConnection(connection), ...result });
      return true;
    }
    if (!match[2] && request.method === "DELETE") {
      delete connections.feeds[id];
      await writeConnections(connections);
      response.writeHead(204, { "cache-control": "no-store" }).end();
      return true;
    }
    json(response, 405, { error: "Method not allowed" });
    return true;
  };
}
