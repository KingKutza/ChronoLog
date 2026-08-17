import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Readable } from "node:stream";
import { createCalendarFeedService, pullHttpsCalendar } from "../tools/calendar-feed-service.js";

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
