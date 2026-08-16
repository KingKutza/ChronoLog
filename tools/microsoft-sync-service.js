import { createHash, randomBytes } from "node:crypto";
import { open, readFile, rename, unlink } from "node:fs/promises";
import { join } from "node:path";
import { serializeComponent } from "../src/ics.js";

const AUTHORITY = "https://login.microsoftonline.com/common/oauth2/v2.0";
const GRAPH = "https://graph.microsoft.com/v1.0";
const SCOPES = "offline_access Calendars.Read Tasks.ReadWrite";
const MAX_GRAPH_PAGES = 100;

function json(response, status, value) {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  response.end(JSON.stringify(value));
}

async function jsonBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 1024 * 1024) throw new RangeError("Microsoft sync request is too large");
    chunks.push(chunk);
  }
  return chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {};
}

function prop(name, value, params = []) {
  return value === undefined || value === null || value === "" ? null : { name, params, value: String(value) };
}

function escapeText(value = "") {
  return String(value).replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/,/g, "\\,").replace(/;/g, "\\;");
}

function utcICS(value, dateOnly = false) {
  if (!value) return null;
  const source = String(value);
  const date = new Date(/(?:Z|[+-]\d{2}:?\d{2})$/i.test(source) ? source : `${source}Z`);
  if (Number.isNaN(date.valueOf())) return null;
  const compact = date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
  return dateOnly ? compact.slice(0, 8) : compact;
}

function graphDate(value, dateOnly = false) {
  return utcICS(value?.dateTime, dateOnly);
}

function calendarComponent(calendar, events) {
  return {
    name: "VCALENDAR",
    properties: [
      prop("VERSION", "2.0"),
      prop("PRODID", "-//ChronoLog//Microsoft Graph adapter//EN"),
      prop("CALSCALE", "GREGORIAN"),
      prop("X-WR-CALNAME", escapeText(calendar.name || "Outlook")),
      prop("X-CHRONOLOG-SOURCE-ID", escapeText(calendar.id))
    ].filter(Boolean),
    components: events.filter((event) => !event["@removed"]).map((event) => {
      const dateOnly = Boolean(event.isAllDay);
      const start = graphDate(event.start, dateOnly);
      const end = graphDate(event.end, dateOnly);
      return {
        name: "VEVENT",
        properties: [
          prop("UID", `${event.id}@microsoft-graph`),
          prop("SUMMARY", escapeText(event.subject || "(untitled)")),
          prop("DESCRIPTION", escapeText(event.bodyPreview || "")),
          prop("LOCATION", escapeText(event.location?.displayName || "")),
          prop("CATEGORIES", (event.categories || []).map(escapeText).join(",")),
          prop("STATUS", String(event.showAs || "").toUpperCase()),
          prop("DTSTART", start, dateOnly ? [{ name: "VALUE", values: ["DATE"] }] : []),
          prop("DTEND", end, dateOnly ? [{ name: "VALUE", values: ["DATE"] }] : []),
          prop("DTSTAMP", utcICS(event.lastModifiedDateTime || event.createdDateTime)),
          prop("X-CHRONOLOG-REVISION", event.changeKey)
        ].filter(Boolean),
        components: []
      };
    })
  };
}

function todoComponent(list, tasks) {
  return {
    name: "VCALENDAR",
    properties: [
      prop("VERSION", "2.0"),
      prop("PRODID", "-//ChronoLog//Microsoft To Do adapter//EN"),
      prop("X-WR-CALNAME", escapeText(`To Do · ${list.displayName || "Tasks"}`)),
      prop("X-CHRONOLOG-SOURCE-ID", escapeText(list.id))
    ].filter(Boolean),
    components: tasks.filter((task) => !task["@removed"]).map((task) => ({
      name: "VTODO",
      properties: [
        prop("UID", `${task.id}@microsoft-todo`),
        prop("SUMMARY", escapeText(task.title || "(untitled)")),
        prop("DESCRIPTION", task.body?.contentType === "text" ? escapeText(task.body.content || "") : ""),
        prop("STATUS", task.status === "completed" ? "COMPLETED" : "NEEDS-ACTION"),
        prop("DTSTART", graphDate(task.dueDateTime)),
        prop("DTSTAMP", utcICS(task.lastModifiedDateTime || task.createdDateTime)),
        prop("COMPLETED", graphDate(task.completedDateTime)),
        prop("CATEGORIES", (task.categories || []).map(escapeText).join(",")),
        prop("X-CHRONOLOG-REVISION", task["@odata.etag"])
      ].filter(Boolean),
      components: []
    }))
  };
}

function calendarText(calendars) {
  return `${calendars.map(serializeComponent).join("\r\n")}\r\n`;
}

function defaultCalendarWindow(now = new Date()) {
  const year = now.getUTCFullYear();
  return { start: `${year - 2}-01-01T00:00:00Z`, end: `${year + 6}-01-01T00:00:00Z` };
}

async function responseJson(response) {
  const text = await response.text();
  let value;
  try { value = text ? JSON.parse(text) : {}; }
  catch { throw new Error(`Microsoft returned an unreadable response (${response.status})`); }
  if (!response.ok) {
    const error = new Error(value.error_description || value.error?.message || value.error || `Microsoft returned ${response.status}`);
    error.code = value.error?.code || value.error;
    error.status = response.status;
    throw error;
  }
  return value;
}

export function createMicrosoftSyncService({ dataRoot, clientId = process.env.CHRONOLOG_MICROSOFT_CLIENT_ID || "", requester = globalThis.fetch } = {}) {
  if (!dataRoot) throw new Error("Microsoft sync service requires a data directory");
  const credentialsFile = join(dataRoot, ".chronolog-microsoft-credentials.json");
  const configFile = join(dataRoot, ".chronolog-microsoft-config.json");
  const sessions = new Map();

  async function configuredClientId() {
    if (clientId) return clientId;
    try { return JSON.parse(await readFile(configFile, "utf8")).clientId || ""; }
    catch (error) { if (error?.code === "ENOENT") return ""; throw error; }
  }

  async function readCredentials() {
    try { return JSON.parse(await readFile(credentialsFile, "utf8")); }
    catch (error) { if (error?.code === "ENOENT") return null; throw error; }
  }

  async function writePrivateJson(file, value) {
    const temporary = join(dataRoot, `.chronolog-microsoft-${process.pid}-${Date.now()}-${randomBytes(4).toString("hex")}.tmp`);
    const descriptor = await open(temporary, "wx", 0o600);
    try {
      await descriptor.writeFile(`${JSON.stringify(value)}\n`);
      await descriptor.sync();
    } finally { await descriptor.close(); }
    try { await rename(temporary, file); }
    finally { await unlink(temporary).catch(() => {}); }
  }

  async function writeCredentials(value) { return writePrivateJson(credentialsFile, value); }

  async function tokenRequest(parameters) {
    const response = await requester(`${AUTHORITY}/token`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(parameters)
    });
    return responseJson(response);
  }

  async function accessToken() {
    const activeClientId = await configuredClientId();
    if (!activeClientId) throw new Error("Configure a Microsoft Entra public-client application ID before syncing");
    const credentials = await readCredentials();
    if (!credentials?.refreshToken) throw new Error("Connect Microsoft before syncing");
    if (credentials.accessToken && Number(credentials.expiresAt) > Date.now() + 60_000) return credentials.accessToken;
    const token = await tokenRequest({
      client_id: activeClientId,
      grant_type: "refresh_token",
      refresh_token: credentials.refreshToken,
      scope: SCOPES
    });
    const next = {
      version: 1,
      refreshToken: token.refresh_token || credentials.refreshToken,
      accessToken: token.access_token,
      expiresAt: Date.now() + Number(token.expires_in || 3600) * 1000,
      scope: token.scope || credentials.scope || SCOPES
    };
    await writeCredentials(next);
    return next.accessToken;
  }

  async function graphPages(path, token) {
    let next = path.startsWith("https://") ? path : `${GRAPH}${path}`;
    const values = [];
    for (let page = 0; next && page < MAX_GRAPH_PAGES; page += 1) {
      if (!next.startsWith(`${GRAPH}/`)) throw new Error("Microsoft pagination attempted to leave Graph v1.0");
      const response = await requester(next, {
        headers: { authorization: `Bearer ${token}`, prefer: 'outlook.timezone="UTC"' }
      });
      const result = await responseJson(response);
      values.push(...(result.value || []));
      next = result["@odata.nextLink"] || null;
    }
    if (next) throw new Error("Microsoft sync exceeded the 100-page safety limit");
    return values;
  }

  async function pullCalendars(input = {}) {
    const token = await accessToken();
    const defaults = defaultCalendarWindow();
    const start = input.start || defaults.start;
    const end = input.end || defaults.end;
    const calendars = await graphPages("/me/calendars?$top=100", token);
    const components = [];
    for (const calendar of calendars) {
      const query = new URLSearchParams({ startDateTime: start, endDateTime: end, $top: "1000" });
      const events = await graphPages(`/me/calendars/${encodeURIComponent(calendar.id)}/calendarView?${query}`, token);
      components.push(calendarComponent(calendar, events));
    }
    if (!components.length) components.push(calendarComponent({ id: "microsoft-calendar-empty", name: "Outlook" }, []));
    const text = calendarText(components);
    return {
      text,
      revision: { digest: createHash("sha256").update(text).digest("hex"), start, end },
      calendars: components.length
    };
  }

  async function pullTasks() {
    const token = await accessToken();
    const lists = await graphPages("/me/todo/lists?$top=100", token);
    const components = [];
    for (const list of lists) {
      const tasks = await graphPages(`/me/todo/lists/${encodeURIComponent(list.id)}/tasks?$top=100`, token);
      components.push(todoComponent(list, tasks));
    }
    if (!components.length) components.push(todoComponent({ id: "microsoft-todo-empty", displayName: "Tasks" }, []));
    const text = calendarText(components);
    return {
      text,
      revision: { digest: createHash("sha256").update(text).digest("hex") },
      calendars: components.length
    };
  }

  return async function handleMicrosoft(request, response, url) {
    if (!url.pathname.startsWith("/api/sync/microsoft")) return false;
    if (url.pathname === "/api/sync/microsoft/status" && request.method === "GET") {
      const activeClientId = await configuredClientId();
      const credentials = await readCredentials();
      json(response, 200, { configured: Boolean(activeClientId), connected: Boolean(activeClientId && credentials?.refreshToken), scopes: SCOPES });
      return true;
    }
    if (url.pathname === "/api/sync/microsoft/config" && request.method === "POST") {
      if (clientId) {
        json(response, 409, { error: "Microsoft client ID is controlled by CHRONOLOG_MICROSOFT_CLIENT_ID for this launcher" });
        return true;
      }
      const input = await jsonBody(request);
      const nextClientId = String(input.clientId || "").trim();
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(nextClientId)) {
        json(response, 400, { error: "Microsoft Application (client) ID must be a UUID" });
        return true;
      }
      await writePrivateJson(configFile, { version: 1, clientId: nextClientId });
      await unlink(credentialsFile).catch((error) => { if (error?.code !== "ENOENT") throw error; });
      json(response, 200, { configured: true, connected: false, scopes: SCOPES });
      return true;
    }
    const activeClientId = await configuredClientId();
    if (!activeClientId) {
      json(response, 503, { error: "Configure a Microsoft Entra public-client application ID before connecting" });
      return true;
    }
    if (url.pathname === "/api/sync/microsoft/connect" && request.method === "POST") {
      const device = await responseJson(await requester(`${AUTHORITY}/devicecode`, {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ client_id: activeClientId, scope: SCOPES })
      }));
      const id = randomBytes(18).toString("base64url");
      sessions.set(id, {
        deviceCode: device.device_code,
        expiresAt: Date.now() + Number(device.expires_in || 900) * 1000,
        interval: Math.max(5, Number(device.interval || 5))
      });
      json(response, 200, {
        session: id,
        userCode: device.user_code,
        verificationUri: device.verification_uri,
        verificationUriComplete: device.verification_uri_complete || null,
        expiresIn: device.expires_in,
        interval: Math.max(5, Number(device.interval || 5))
      });
      return true;
    }
    const poll = /^\/api\/sync\/microsoft\/connect\/([^/]+)\/poll$/.exec(url.pathname);
    if (poll && request.method === "POST") {
      const session = sessions.get(decodeURIComponent(poll[1]));
      if (!session || session.expiresAt <= Date.now()) {
        json(response, 410, { error: "Microsoft sign-in expired; start again" });
        return true;
      }
      try {
        const token = await tokenRequest({
          client_id: activeClientId,
          grant_type: "urn:ietf:params:oauth:grant-type:device_code",
          device_code: session.deviceCode
        });
        await writeCredentials({
          version: 1,
          refreshToken: token.refresh_token,
          accessToken: token.access_token,
          expiresAt: Date.now() + Number(token.expires_in || 3600) * 1000,
          scope: token.scope || SCOPES
        });
        sessions.delete(decodeURIComponent(poll[1]));
        json(response, 200, { connected: true });
      } catch (error) {
        if (["authorization_pending", "slow_down"].includes(error.code)) {
          json(response, 202, { connected: false, pending: true, interval: session.interval + (error.code === "slow_down" ? 5 : 0) });
        } else throw error;
      }
      return true;
    }
    if (url.pathname === "/api/sync/microsoft/disconnect" && request.method === "POST") {
      await unlink(credentialsFile).catch((error) => { if (error?.code !== "ENOENT") throw error; });
      json(response, 200, { connected: false });
      return true;
    }
    if (url.pathname === "/api/sync/microsoft/calendar/pull" && request.method === "POST") {
      const input = await jsonBody(request);
      json(response, 200, await pullCalendars(input));
      return true;
    }
    if (url.pathname === "/api/sync/microsoft/todo/pull" && request.method === "POST") {
      json(response, 200, await pullTasks());
      return true;
    }
    json(response, 405, { error: "Method not allowed" });
    return true;
  };
}

export const MICROSOFT_SYNC_SCOPES = SCOPES;
