import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Readable } from "node:stream";
import { createCalendarFeedService, normalizeFeedUrlScheme, pinnedLookup, pullHttpsCalendar } from "../tools/calendar-feed-service.js";

function request(method, body = null) {
  const value = body === null ? [] : [Buffer.from(JSON.stringify(body))];
  const stream = Readable.from(value);
  stream.method = method;
  return stream;
}

function response() {
  return {
    status: null,
    headers: null,
    body: "",
    writeHead(status, headers = {}) { this.status = status; this.headers = headers; return this; },
    end(body = "") { this.body += body; return this; }
  };
}

async function call(service, method, path, body = null) {
  const output = response();
  const handled = await service(request(method, body), output, new URL(path, "http://localhost"));
  assert.equal(handled, true);
  return output;
}

test("calendar feed connections keep secret URLs server-side and pull with document-owned revisions", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-calendar-feeds-"));
  const calls = [];
  const service = createCalendarFeedService({
    dataRoot: root,
    async pullFeed(url, revision) {
      calls.push({ url, revision });
      return { notModified: false, revision: { etag: '"two"' }, text: "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n" };
    }
  });
  try {
    const created = await call(service, "POST", "/api/sync/feeds", {
      label: "Work", url: "https://calendar.example/work.ics?token=top-secret"
    });
    assert.equal(created.status, 201);
    const connection = JSON.parse(created.body);
    assert.equal(connection.urlHint, "https://calendar.example");
    assert.doesNotMatch(created.body, /top-secret/);

    const listed = await call(service, "GET", "/api/sync/connections");
    assert.equal(listed.status, 200);
    assert.doesNotMatch(listed.body, /top-secret/);
    const pulled = await call(service, "POST", `/api/sync/feeds/${encodeURIComponent(connection.id)}/pull`, {
      revision: { etag: '"one"' }
    });
    assert.equal(pulled.status, 200);
    assert.deepEqual(calls, [{
      url: "https://calendar.example/work.ics?token=top-secret", revision: { etag: '"one"' }
    }]);
    assert.match(JSON.parse(pulled.body).text, /VCALENDAR/);

    const config = join(root, ".chronolog-calendar-connections.json");
    assert.match(await readFile(config, "utf8"), /top-secret/);
    if (process.platform !== "win32") {
      assert.equal((await stat(config)).mode & 0o777, 0o600);
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("remote calendar fetch refuses loopback targets before making a request", async () => {
  await assert.rejects(pullHttpsCalendar("https://127.0.0.1/private.ics"), /private or reserved/);
});

test("normalizeFeedUrlScheme rewrites webcal(s) to https and leaves everything else untouched", () => {
  assert.equal(
    normalizeFeedUrlScheme("webcal://calendar.example/astro.ics"),
    "https://calendar.example/astro.ics"
  );
  assert.equal(
    normalizeFeedUrlScheme("webcals://calendar.example/astro.ics"),
    "https://calendar.example/astro.ics"
  );
  assert.equal(
    normalizeFeedUrlScheme("WEBCAL://Calendar.Example/astro.ICS?x=1#frag"),
    "https://Calendar.Example/astro.ICS?x=1#frag"
  );
  // Credentials, ports, and percent-encoding all sit after the scheme and
  // must survive untouched — normalization only ever rewrites the prefix.
  assert.equal(
    normalizeFeedUrlScheme("webcal://user:pass@host.example:8443/a%20b.ics"),
    "https://user:pass@host.example:8443/a%20b.ics"
  );
  // Already-https and unrelated schemes pass through unchanged.
  assert.equal(normalizeFeedUrlScheme("https://calendar.example/a.ics"), "https://calendar.example/a.ics");
  assert.equal(normalizeFeedUrlScheme("http://calendar.example/a.ics"), "http://calendar.example/a.ics");
  // A hostname that merely starts with "webcal" is not the scheme and must
  // not be touched.
  assert.equal(normalizeFeedUrlScheme("https://webcal.example/a.ics"), "https://webcal.example/a.ics");
});

test("calendar feed subscriptions accept webcal(s) addresses, normalized to https before storage", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-calendar-feeds-webcal-"));
  const service = createCalendarFeedService({
    dataRoot: root,
    async pullFeed() { throw new Error("pull should not run for this test"); }
  });
  try {
    const created = await call(service, "POST", "/api/sync/feeds", {
      label: "Astronomy", url: "WEBCAL://calendar.example/astrocal.ics?x=1#frag"
    });
    assert.equal(created.status, 201);
    const connection = JSON.parse(created.body);
    assert.equal(connection.urlHint, "https://calendar.example");

    const config = join(root, ".chronolog-calendar-connections.json");
    const stored = JSON.parse(await readFile(config, "utf8"));
    const storedUrl = Object.values(stored.feeds)[0].url;
    assert.equal(storedUrl, "https://calendar.example/astrocal.ics?x=1#frag");

    const secondary = await call(service, "POST", "/api/sync/feeds", {
      label: "Secure webcal", url: "webcals://calendar.example/other.ics"
    });
    assert.equal(secondary.status, 201);
    assert.equal(JSON.parse(secondary.body).urlHint, "https://calendar.example");
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("calendar feed subscriptions still refuse plain http, even disguised behind webcal normalization", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-calendar-feeds-http-"));
  const service = createCalendarFeedService({ dataRoot: root });
  try {
    await assert.rejects(
      call(service, "POST", "/api/sync/feeds", { label: "Plain", url: "http://calendar.example/a.ics" }),
      /HTTPS/
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("a webcal(s) URL aimed at a private or reserved target is rejected exactly like its https equivalent", async () => {
  await assert.rejects(pullHttpsCalendar("webcal://127.0.0.1/private.ics"), /private or reserved/);
  await assert.rejects(pullHttpsCalendar("webcals://169.254.169.254/private.ics"), /private or reserved/);
  await assert.rejects(pullHttpsCalendar("WEBCAL://[::1]/private.ics"), /private or reserved/);
});

test("a webcal URL targeting this device by name is still rejected, without ever attempting DNS or a fetch", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-calendar-feeds-localhost-"));
  const service = createCalendarFeedService({
    dataRoot: root,
    async pullFeed() { throw new Error("pull should not run for this test"); }
  });
  try {
    await assert.rejects(
      call(service, "POST", "/api/sync/feeds", { label: "Local", url: "webcal://localhost/a.ics" }),
      /private network/
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

// --- resolver-shape regression -------------------------------------------
//
// The field bug: a real HTTPS fetch to a plain public hostname failed with
// Node's own "Invalid IP address: undefined", for every subscription URL
// including the owner's exact webcal:// and https:// reports. Root cause:
// `requestCalendar` pins the already-validated address by handing
// `net`/`tls`/`https` a custom `lookup` option, but Node's connection layer
// calls that option exactly like a DNS resolver and its calling shape is
// not fixed. Happy Eyeballs (`autoSelectFamily`, default-on since Node 20)
// asks for `options.all` and requires the callback answered as an array of
// `{address, family}` (the same shape `dns.promises.lookup` uses for
// `{all: true}`); a plain connect asks for the classic single
// `(address, family)` form. The old code answered unconditionally in the
// classic shape, so Node's array-expecting path received a bare number
// where it expected a list and failed downstream. `pinnedLookup` is the
// fix: it answers in whichever shape was actually requested.
test("pinnedLookup answers Node's own array-shaped lookup contract (options.all), not just the classic one", () => {
  const lookup = pinnedLookup({ address: "93.184.216.34", family: 4 });

  // This is the exact call shape Node's Happy Eyeballs connect path makes
  // (verified against a live https.request: `{hints: 0, all: true}`). A
  // pre-fix `lookup` answered `callback(null, "93.184.216.34", 4)` here,
  // which is not an array — the assertion below fails against that shape.
  let allShapeResult;
  lookup("ignored.example", { all: true, hints: 0 }, (err, addresses) => {
    assert.equal(err, null);
    allShapeResult = addresses;
  });
  assert.deepEqual(allShapeResult, [{ address: "93.184.216.34", family: 4 }]);

  // The classic single-address shape must still work for callers that don't
  // request `all`.
  let classicAddress;
  let classicFamily;
  lookup("ignored.example", {}, (err, address, family) => {
    assert.equal(err, null);
    classicAddress = address;
    classicFamily = family;
  });
  assert.equal(classicAddress, "93.184.216.34");
  assert.equal(classicFamily, 4);
});

// --- full pipeline, stubbed DNS + HTTP layer ------------------------------
//
// These exercise `pullHttpsCalendar`'s real `resolvedPublicAddress` guard
// (the same BlockList used against live traffic) against fabricated
// resolver answers, and a fabricated HTTP layer for response/redirect
// shaping — no live network call anywhere in this block.

function stubResolver(byHostname) {
  return async (hostname) => {
    const answer = byHostname[hostname];
    if (!answer) throw new Error(`stubResolver: no answer configured for ${hostname}`);
    return answer;
  };
}

function stubSender(responses) {
  let call = 0;
  return async (url, address, headers) => {
    const step = responses[Math.min(call, responses.length - 1)];
    call += 1;
    return typeof step === "function" ? step(url, address, headers) : step;
  };
}

function icsResponse(body = "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n") {
  return { status: 200, headers: { "content-type": "text/calendar" }, body: Buffer.from(body) };
}

test("a public hostname resolving to a public IPv4 address succeeds through the stubbed pipeline", async () => {
  const result = await pullHttpsCalendar("https://calendar.example/a.ics", {}, 0, {
    resolveHost: stubResolver({ "calendar.example": [{ address: "93.184.216.34", family: 4 }] }),
    sendRequest: stubSender([icsResponse()])
  });
  assert.match(result.text, /VCALENDAR/);
});

test("a public hostname resolving to a private IPv4 address is rejected before any fetch happens", async () => {
  await assert.rejects(
    pullHttpsCalendar("https://calendar.example/a.ics", {}, 0, {
      resolveHost: stubResolver({ "calendar.example": [{ address: "10.1.2.3", family: 4 }] }),
      sendRequest: stubSender([() => { throw new Error("fetch should not run for a private answer"); }])
    }),
    /private or reserved/
  );
});

test("a public hostname resolving to a public IPv6 address succeeds through the stubbed pipeline", async () => {
  const result = await pullHttpsCalendar("https://calendar.example/a.ics", {}, 0, {
    resolveHost: stubResolver({ "calendar.example": [{ address: "2606:2800:220:1:248:1893:25c8:1946", family: 6 }] }),
    sendRequest: stubSender([icsResponse()])
  });
  assert.match(result.text, /VCALENDAR/);
});

test("a public hostname resolving to a private/unique-local IPv6 address is rejected", async () => {
  await assert.rejects(
    pullHttpsCalendar("https://calendar.example/a.ics", {}, 0, {
      // fc00::/7 unique local
      resolveHost: stubResolver({ "calendar.example": [{ address: "fd12:3456:789a::1", family: 6 }] }),
      sendRequest: stubSender([() => { throw new Error("fetch should not run for a private answer"); }])
    }),
    /private or reserved/
  );
});

test("an IPv4-mapped IPv6 answer that maps to a private address is rejected, not unwrapped into an allow", async () => {
  await assert.rejects(
    pullHttpsCalendar("https://calendar.example/a.ics", {}, 0, {
      resolveHost: stubResolver({ "calendar.example": [{ address: "::ffff:127.0.0.1", family: 6 }] }),
      sendRequest: stubSender([() => { throw new Error("fetch should not run for a private answer"); }])
    }),
    /private or reserved/
  );
});

test("webcal:// is normalized to https:// before the stubbed pipeline resolves or fetches anything", async () => {
  let requestedProtocol = null;
  const result = await pullHttpsCalendar("webcal://calendar.example/a.ics", {}, 0, {
    resolveHost: stubResolver({ "calendar.example": [{ address: "93.184.216.34", family: 4 }] }),
    sendRequest: stubSender([(url) => { requestedProtocol = url.protocol; return icsResponse(); }])
  });
  assert.equal(requestedProtocol, "https:");
  assert.match(result.text, /VCALENDAR/);
});

test("a redirect to a private-network host is rejected: every hop is re-validated, not just the first", async () => {
  await assert.rejects(
    pullHttpsCalendar("https://calendar.example/a.ics", {}, 0, {
      resolveHost: stubResolver({
        "calendar.example": [{ address: "93.184.216.34", family: 4 }],
        "internal.calendar.example": [{ address: "192.168.1.5", family: 4 }]
      }),
      sendRequest: stubSender([
        { status: 302, headers: { location: "https://internal.calendar.example/a.ics" }, body: Buffer.alloc(0) },
        () => { throw new Error("fetch should not run for the redirected private hop"); }
      ])
    }),
    /private or reserved/
  );
});

test("a redirect chain across public hosts is followed and each hop is validated", async () => {
  const result = await pullHttpsCalendar("https://calendar.example/a.ics", {}, 0, {
    resolveHost: stubResolver({
      "calendar.example": [{ address: "93.184.216.34", family: 4 }],
      "mirror.calendar.example": [{ address: "185.199.108.153", family: 4 }]
    }),
    sendRequest: stubSender([
      { status: 301, headers: { location: "https://mirror.calendar.example/a.ics" }, body: Buffer.alloc(0) },
      icsResponse()
    ])
  });
  assert.match(result.text, /VCALENDAR/);
});
