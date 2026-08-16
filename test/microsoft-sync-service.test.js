import test from "node:test";
import assert from "node:assert/strict";
import { access, mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Readable } from "node:stream";
import { createMicrosoftSyncService, MICROSOFT_SYNC_SCOPES } from "../tools/microsoft-sync-service.js";
import { applyICSSnapshot } from "../src/calendar-sync.js";
import { createCelestialDocument } from "../src/celestial.js";
import { validateDocument } from "../src/model.js";

function request(method, body = null) {
  const stream = Readable.from(body === null ? [] : [Buffer.from(JSON.stringify(body))]);
  stream.method = method;
  return stream;
}

function response() {
  return {
    status: null, body: "",
    writeHead(status) { this.status = status; return this; },
    end(body = "") { this.body += body; return this; }
  };
}

async function call(service, method, path, body = null) {
  const output = response();
  assert.equal(await service(request(method, body), output, new URL(path, "http://localhost")), true);
  return { status: output.status, value: output.body ? JSON.parse(output.body) : null };
}

function result(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json" } });
}

test("Microsoft device authorization stores tokens locally and pulls Outlook and To Do as ICS snapshots", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-microsoft-sync-"));
  let polls = 0;
  const graphAuthorizations = [];
  const requester = async (url, options = {}) => {
    if (url.endsWith("/devicecode")) return result({
      device_code: "device-secret", user_code: "ABCD-EFGH", verification_uri: "https://microsoft.com/devicelogin",
      expires_in: 900, interval: 5
    });
    if (url.endsWith("/token")) {
      const grant = String(options.body.get("grant_type"));
      if (grant.includes("device_code") && polls++ === 0) return result({ error: "authorization_pending" }, 400);
      return result({ access_token: "access-secret", refresh_token: "refresh-secret", expires_in: 3600, scope: MICROSOFT_SYNC_SCOPES });
    }
    graphAuthorizations.push(options.headers.authorization);
    if (url.includes("/me/calendars?")) return result({ value: [{ id: "calendar-1", name: "Outlook Work" }] });
    if (url.includes("/calendarView?")) return result({ value: [{
      id: "event-1", subject: "Planning", bodyPreview: "Quarterly plan", categories: ["Work"],
      start: { dateTime: "2026-08-16T12:00:00", timeZone: "UTC" },
      end: { dateTime: "2026-08-16T13:00:00", timeZone: "UTC" },
      createdDateTime: "2026-08-01T10:00:00Z", changeKey: "event-revision"
    }] });
    if (url.includes("/me/todo/lists?")) return result({ value: [{ id: "list-1", displayName: "Tasks" }] });
    if (url.includes("/tasks?")) return result({ value: [{
      id: "task-1", title: "File report", status: "notStarted", categories: ["Work"],
      dueDateTime: { dateTime: "2026-08-17T17:00:00", timeZone: "UTC" },
      createdDateTime: "2026-08-01T10:00:00Z", "@odata.etag": "task-revision"
    }] });
    throw new Error(`Unexpected request ${url}`);
  };
  const service = createMicrosoftSyncService({ dataRoot: root, clientId: "public-client-id", requester });
  try {
    const started = await call(service, "POST", "/api/sync/microsoft/connect");
    assert.equal(started.value.userCode, "ABCD-EFGH");
    assert.doesNotMatch(JSON.stringify(started.value), /device-secret/);
    const pending = await call(service, "POST", `/api/sync/microsoft/connect/${started.value.session}/poll`);
    assert.equal(pending.status, 202);
    const connected = await call(service, "POST", `/api/sync/microsoft/connect/${started.value.session}/poll`);
    assert.equal(connected.value.connected, true);

    const credentials = join(root, ".chronolog-microsoft-credentials.json");
    assert.match(await readFile(credentials, "utf8"), /refresh-secret/);
    assert.equal((await stat(credentials)).mode & 0o777, 0o600);
    const status = await call(service, "GET", "/api/sync/microsoft/status");
    assert.deepEqual(status.value, { configured: true, connected: true, scopes: MICROSOFT_SYNC_SCOPES });

    const calendar = await call(service, "POST", "/api/sync/microsoft/calendar/pull");
    assert.match(calendar.value.text, /X-WR-CALNAME:Outlook Work/);
    assert.match(calendar.value.text, /UID:event-1@microsoft-graph/);
    assert.match(calendar.value.text, /DTSTART:20260816T120000Z/);
    const todo = await call(service, "POST", "/api/sync/microsoft/todo/pull");
    assert.match(todo.value.text, /BEGIN:VTODO/);
    assert.match(todo.value.text, /SUMMARY:File report/);
    const document = createCelestialDocument();
    applyICSSnapshot(document, { connectionId: "microsoft:calendar", text: calendar.value.text, provider: "microsoft-calendar" });
    applyICSSnapshot(document, { connectionId: "microsoft:todo", text: todo.value.text, provider: "microsoft-todo" });
    assert.ok(Object.values(document.events).some((event) => event.payload.title === "Planning"));
    assert.ok(Object.values(document.events).some((event) => event.payload.title === "File report" && event.traits.includes("task")));
    const validation = validateDocument(document);
    assert.equal(validation.valid, true, validation.errors.join("\n"));
    assert.ok(graphAuthorizations.every((value) => value === "Bearer access-secret"));

    await call(service, "POST", "/api/sync/microsoft/disconnect");
    await assert.rejects(access(credentials), /ENOENT/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("a public Microsoft client ID can be configured locally without storing a client secret", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-microsoft-config-"));
  const service = createMicrosoftSyncService({ dataRoot: root, clientId: "", requester: async () => { throw new Error("not expected"); } });
  try {
    assert.equal((await call(service, "GET", "/api/sync/microsoft/status")).value.configured, false);
    const configured = await call(service, "POST", "/api/sync/microsoft/config", {
      clientId: "11111111-2222-4333-8444-555555555555"
    });
    assert.equal(configured.value.configured, true);
    assert.equal((await call(service, "GET", "/api/sync/microsoft/status")).value.configured, true);
    const file = join(root, ".chronolog-microsoft-config.json");
    assert.doesNotMatch(await readFile(file, "utf8"), /secret/i);
    assert.equal((await stat(file)).mode & 0o777, 0o600);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
