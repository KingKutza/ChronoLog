import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Readable } from "node:stream";
import { createCalendarFeedService, normalizeFeedUrlScheme, pullHttpsCalendar } from "../tools/calendar-feed-service.js";

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
